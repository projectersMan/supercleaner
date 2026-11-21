import assert from 'node:assert/strict';
import { spawnSync } from 'node:child_process';
import { generateKeyPairSync, randomBytes, randomUUID, sign, verify } from 'node:crypto';
import { once } from 'node:events';
import { request as httpRequest } from 'node:http';
import { chmodSync, mkdirSync, mkdtempSync, readFileSync, rmSync, statSync, writeFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { afterEach, test } from 'node:test';
import { CommerceService, ServiceFault, validateConfiguration, canonicalParameters, verifyAlipayResponse } from '../../CommerceService/commerce.mjs';
import { createHTTPServer } from '../../CommerceService/http.mjs';

const email = 'buyer@example.com';
const deviceID = randomUUID();
const activeFixtures = new Set();

async function cleanupFixtures() {
  for (const fixture of activeFixtures) {
    if (fixture.server !== undefined && fixture.server.server.listening) await fixture.server.close();
    fixture.close();
  }
}

afterEach(cleanupFixtures);

class Fixture {
  constructor() {
    mkdirSync(resolve('Tests/temporary'), { recursive: true });
    this.directory = mkdtempSync(resolve('Tests/temporary/commercial-launch-'));
    activeFixtures.add(this);
    this.alipayKeys = generateKeyPairSync('rsa', { modulusLength: 2048 });
    this.merchantKeys = generateKeyPairSync('rsa', { modulusLength: 2048 });
    this.licenseKeys = generateKeyPairSync('ed25519');
    this.proxySharedSecret = randomBytes(32).toString('base64url');
    writeFileSync(resolve(this.directory, 'merchant.pem'), this.merchantKeys.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
    writeFileSync(resolve(this.directory, 'alipay.pem'), this.alipayKeys.publicKey.export({ type: 'spki', format: 'pem' }));
    writeFileSync(resolve(this.directory, 'license.pem'), this.licenseKeys.privateKey.export({ type: 'pkcs8', format: 'pem' }), { mode: 0o600 });
    writeFileSync(resolve(this.directory, 'encryption.key'), randomBytes(32), { mode: 0o600 });
    writeFileSync(resolve(this.directory, 'proxy.key'), Buffer.from(this.proxySharedSecret, 'base64url'), { mode: 0o600 });
    this.rawConfiguration = {
      schemaVersion: 1, host: '127.0.0.1', port: 8432, publicBaseURL: 'https://pay.example.com',
      productID: 'supercleaner.buyout', productName: 'SuperCleaner 永久买断', priceCents: 9900,
      deviceLimit: 2, offlineLeaseSeconds: 604800, orderTTLSeconds: 1800,
      rateLimitWindowSeconds: 60, requestRateLimitMax: 300, orderRateLimitMax: 20,
      requestBodyLimitBytes: 16384, requestTimeoutMilliseconds: 10000, upstreamTimeoutMilliseconds: 10000,
      alipayGateway: 'https://openapi.alipay.com/gateway.do', alipayAppID: '2026000000000000', alipaySellerID: '2088000000000000',
      alipayPrivateKeyPath: resolve(this.directory, 'merchant.pem'), alipayPublicKeyPath: resolve(this.directory, 'alipay.pem'),
      licensePrivateKeyPath: resolve(this.directory, 'license.pem'), licenseEncryptionKeyPath: resolve(this.directory, 'encryption.key'),
      databasePath: resolve(this.directory, 'commerce.sqlite'), proxySharedSecretPath: resolve(this.directory, 'proxy.key'),
    };
    this.configuration = validateConfiguration(this.rawConfiguration);
    this.service = new CommerceService(this.configuration);
  }
  close() {
    if (this.service !== undefined && this.service.database.isOpen) this.service.close();
    rmSync(this.directory, { recursive: true, force: true });
    activeFixtures.delete(this);
  }
  proxyHeaders() { return { 'x-real-ip': '198.51.100.1', 'x-supercleaner-proxy-token': this.proxySharedSecret }; }
  order() { return this.service.createOrder({ email, deviceID }); }
  notification(order, changes) {
    const fields = {
      app_id: this.configuration.alipayAppID, seller_id: this.configuration.alipaySellerID,
      out_trade_no: order.orderID.replaceAll('-', ''), total_amount: '99.00', trade_no: `20261121${order.orderID.replaceAll('-', '')}`,
      trade_status: 'TRADE_SUCCESS', charset: 'utf-8', sign_type: 'RSA2', ...changes,
    };
    fields.sign = sign('RSA-SHA256', Buffer.from(canonicalParameters(fields, true)), this.alipayKeys.privateKey).toString('base64');
    return fields;
  }
  paidOrder() {
    const order = this.order();
    assert.equal(this.service.processNotification(this.notification(order, {})), 'success');
    return { ...order, licenseKey: this.service.orderStatus(order).licenseKey };
  }
  credentials(order, changes) { return { email, licenseKey: order.licenseKey, deviceID, deviceName: 'MacBook', ...changes }; }
}

function rejectFault(result, status) {
  assert.ok(result instanceof ServiceFault);
  assert.equal(result.status, status);
}
function invalidConfiguration() {
  const f = new Fixture();
  const missing = { ...f.rawConfiguration };
  delete missing.priceCents;
  assert.throws(validateConfiguration.bind(null, missing), /priceCents/);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, typo: 1 }), /typo/);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, publicBaseURL: 'http://pay.example.com' }), /HTTPS/);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, priceCents: 1.5 }), /priceCents/);
  f.close();
}
function orderPrivacy() {
  const f = new Fixture();
  const order = f.order();
  assert.equal(Buffer.from(order.pollToken, 'base64url').length, 32);
  assert.equal(new URL(order.checkoutURL).origin, 'https://pay.example.com');
  assert.deepEqual(f.service.orderStatus(order), { status: 'pending', licenseKey: null });
  rejectFault(f.service.orderStatus({ orderID: order.orderID, pollToken: randomBytes(32).toString('base64url') }), 403);
  rejectFault(f.service.orderStatus({ orderID: randomUUID(), pollToken: order.pollToken }), 403);
  const stored = f.service.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(order.orderID);
  assert.equal(stored.poll_token, undefined);
  assert.ok(stored.poll_token_hash);
  f.close();
}
function rejectBadNotifications() {
  const f = new Fixture();
  const order = f.order();
  const cases = [
    { app_id: '2026000000000001' }, { seller_id: '2088000000000001' }, { total_amount: '98.99' },
    { total_amount: '9.9e1' }, { total_amount: '99.001' }, { trade_no: '' }, { trade_status: 'UNKNOWN' },
    { out_trade_no: randomUUID() }, { charset: 'gbk' }, { sign_type: 'RSA' },
  ];
  for (const changes of cases) rejectFault(f.service.processNotification(f.notification(order, changes)), 400);
  const forged = f.notification(order, {});
  forged.total_amount = '100.00';
  rejectFault(f.service.processNotification(forged), 400);
  assert.equal(f.service.orderStatus(order).status, 'pending');
  f.close();
}
function paymentIdempotencyAndSignatures() {
  const f = new Fixture();
  const order = f.paidOrder();
  assert.equal(f.service.processNotification(f.notification(order, {})), 'success');
  assert.equal(f.service.orderStatus(order).licenseKey, order.licenseKey);
  rejectFault(f.service.processNotification(f.notification(order, { trade_no: 'different-trade' })), 400);
  const secondOrder = f.order();
  rejectFault(f.service.processNotification(f.notification(secondOrder, { trade_no: f.notification(order, {}).trade_no })), 400);
  const signed = f.service.activate(f.credentials(order, {}));
  assert.ok(verify(null, Buffer.from(signed.claimsData, 'base64'), f.licenseKeys.publicKey, Buffer.from(signed.signature, 'base64')));
  const claims = JSON.parse(Buffer.from(signed.claimsData, 'base64'));
  assert.deepEqual(Object.keys(claims).sort(), ['licenseID','productID','email','deviceID','issuedAt','offlineValidUntil','capabilities'].sort());
  assert.equal(claims.productID, f.configuration.productID);
  assert.equal(claims.deviceID, deviceID);
  assert.equal(claims.offlineValidUntil - claims.issuedAt, 604800);
  assert.deepEqual(claims.capabilities, ['standardScan', 'agentScan', 'newCleanup']);
  assert.equal(f.service.database.prepare('SELECT COUNT(*) AS count FROM licenses').get().count, 1);
  const data = readFileSync(f.configuration.databasePath);
  assert.equal(data.includes(Buffer.from(order.licenseKey)), false);
  f.close();
}
function refundsCannotResurrect() {
  const f = new Fixture();
  const order = f.paidOrder();
  assert.ok(f.service.activate(f.credentials(order, {})).signature);
  assert.equal(f.service.processNotification(f.notification(order, { refund_fee: '1.00' })), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  assert.equal(f.service.orderStatus(order).licenseKey, null);
  assert.equal(f.service.processNotification(f.notification(order, {})), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  rejectFault(f.service.activate(f.credentials(order, {})), 403);
  rejectFault(f.service.refresh(f.credentials(order, {})), 403);
  f.close();
}
function closedOrdersCannotResurrect() {
  const f = new Fixture();
  const order = f.order();
  assert.equal(f.service.processNotification(f.notification(order, { trade_status: 'TRADE_CLOSED' })), 'success');
  assert.equal(f.service.processNotification(f.notification(order, {})), 'success');
  assert.equal(f.service.orderStatus(order).status, 'closed');
  const paid = f.paidOrder();
  assert.equal(f.service.processNotification(f.notification(paid, { trade_status: 'TRADE_CLOSED' })), 'success');
  assert.equal(f.service.orderStatus(paid).status, 'revoked');
  f.close();
}
function refundBeforeSuccessPersists() {
  const f = new Fixture();
  const order = f.order();
  assert.equal(f.service.processNotification(f.notification(order, { refund_fee: '99.00' })), 'success');
  assert.equal(f.service.processNotification(f.notification(order, {})), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  assert.equal(f.service.database.prepare('SELECT COUNT(*) AS count FROM licenses').get().count, 0);
  f.close();
}
function deviceLimitAndPersistentDeactivation() {
  const f = new Fixture();
  const order = f.paidOrder();
  const secondDevice = randomUUID();
  assert.ok(f.service.activate(f.credentials(order, {})).signature);
  assert.ok(f.service.activate(f.credentials(order, {})).signature);
  assert.ok(f.service.activate(f.credentials(order, { deviceID: secondDevice })).signature);
  rejectFault(f.service.activate(f.credentials(order, { deviceID: randomUUID() })), 409);
  assert.equal(f.service.devices({ email, licenseKey: order.licenseKey }).devices.length, 2);
  assert.deepEqual(f.service.deactivate(f.credentials(order, {})), { deactivated: true });
  assert.deepEqual(f.service.deactivate(f.credentials(order, {})), { deactivated: true });
  rejectFault(f.service.refresh(f.credentials(order, {})), 403);
  f.service.close();
  f.service = new CommerceService(f.configuration);
  rejectFault(f.service.refresh(f.credentials(order, {})), 403);
  assert.equal(f.service.devices({ email, licenseKey: order.licenseKey }).devices.length, 1);
  assert.ok(f.service.activate(f.credentials(order, { deviceID: randomUUID() })).signature);
  f.close();
}
async function concurrentDeviceLimit() {
  const f = new Fixture();
  const order = f.paidOrder();
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  const address = server.address();
  const requests = [];
  for (let i = 0; i < 12; i += 1) requests.push(fetch(`http://127.0.0.1:${address.port}/v1/licenses/activate`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json' }, body: JSON.stringify(f.credentials(order, { deviceID: randomUUID() })) }));
  const responses = await Promise.all(requests);
  let successful = 0;
  for (const response of responses) { if (response.status === 200) successful += 1; else assert.equal(response.status, 409); }
  assert.equal(successful, 2);
  assert.equal(f.service.devices({ email, licenseKey: order.licenseKey }).devices.length, 2);
  await server.close();
  f.close();
}
function manualRevocationPersists() {
  const f = new Fixture();
  const order = f.paidOrder();
  assert.deepEqual(f.service.revokeOrder(order.orderID, '支付宝商家账单已退款'), { status: 'revoked' });
  f.service.close();
  f.service = new CommerceService(f.configuration);
  assert.equal(f.service.processNotification(f.notification(order, {})), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  assert.equal(f.service.database.prepare('SELECT COUNT(*) AS count FROM audit_events').get().count > 0, true);
  f.close();
}
async function checkoutAndHTTPBoundaries() {
  const f = new Fixture();
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  const base = `http://127.0.0.1:${server.address().port}`;
  const orderResponse = await fetch(`${base}/v1/orders`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json' }, body: JSON.stringify({ email, deviceID }) });
  assert.equal(orderResponse.status, 200);
  assert.equal(orderResponse.headers.get('access-control-allow-origin'), null);
  const order = await orderResponse.json();
  const page = await fetch(`${base}/checkout/${order.orderID}?token=${order.pollToken}`, { headers: f.proxyHeaders() });
  assert.equal(page.status, 200);
  assert.equal(page.headers.get('cache-control'), 'no-store');
  assert.equal(page.headers.get('referrer-policy'), 'no-referrer');
  assert.ok(page.headers.get('content-security-policy').includes("default-src 'none'"));
  const html = await page.text();
  assert.ok(html.includes('alipay.trade.page.pay'));
  assert.ok(html.includes('FAST_INSTANT_TRADE_PAY'));
  assert.equal(html.includes(order.pollToken), false);
  assert.equal(html.includes('<script'), false);
  assert.ok(html.includes('有效期为7天'));
  assert.ok(html.includes('退款或解绑后，离线授权最迟在7天内失效'));
  assert.equal(html.includes('604800'), false);
  const missingToken = await fetch(`${base}/checkout/${order.orderID}`, { headers: f.proxyHeaders() });
  assert.equal(missingToken.status, 403);
  const crossOrigin = await fetch(`${base}/v1/orders/status`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json', origin: 'https://evil.example' }, body: JSON.stringify(order) });
  assert.equal(crossOrigin.status, 403);
  const malformed = await fetch(`${base}/v1/orders`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json' }, body: '{' });
  assert.equal(malformed.status, 400);
  const duplicate = await fetch(`${base}/v1/alipay/notify`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/x-www-form-urlencoded' }, body: 'sign=a&sign=b' });
  assert.equal(duplicate.status, 400);
  const oversize = await fetch(`${base}/v1/orders`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json' }, body: JSON.stringify({ email: 'a'.repeat(20000), deviceID }) });
  assert.equal(oversize.status, 413);
  await server.close();
  f.close();
}
function signedGatewayResponses() {
  const f = new Fixture();
  const raw = '{"code":"10000", "msg":"Success", "out_trade_no":"a", "memo":"} and \\\" tricky"}';
  const signature = sign('RSA-SHA256', Buffer.from(raw), f.alipayKeys.privateKey).toString('base64');
  const body = `{"alipay_trade_query_response":${raw},"sign":"${signature}"}`;
  assert.equal(verifyAlipayResponse(body, 'alipay.trade.query', f.configuration.alipayPublicKey).code, '10000');
  rejectFault(verifyAlipayResponse(body.replace('Success', 'Forged'), 'alipay.trade.query', f.configuration.alipayPublicKey), 502);
  f.close();
}

test('必填配置、未知字段、HTTPS 和整数金额严格校验', invalidConfiguration);
test('订单凭证为 256 bit 且数据库仅存哈希，未知订单不泄漏', orderPrivacy);
test('真实 RSA2 拒绝伪签名、错金额、错商户、未知状态与订单', rejectBadNotifications);
test('支付幂等、交易号唯一，签发真实 Ed25519 短期租约', paymentIdempotencyAndSignatures);
test('部分退款立即撤销，旧成功通知不能复活授权', refundsCannotResurrect);
test('关闭状态单调，已付款关闭撤销授权', closedOrdersCannotResurrect);
test('先到退款后到成功仍保持撤销', refundBeforeSuccessPersists);
test('设备上限、同机幂等、持久解绑、刷新不重新激活', deviceLimitAndPersistentDeactivation);
test('并发 HTTP 激活仍严格限制设备数', concurrentDeviceLimit);
test('管理撤销持久化并审计，重启重放不复活', manualRevocationPersists);
test('结账页及 HTTP 防跨源、无凭证、解析和体积边界', checkoutAndHTTPBoundaries);
test('支付宝响应使用原始 JSON 验签，拒绝篡改', signedGatewayResponses);

function alipayCheckoutProtocol() {
  const f = new Fixture();
  const order = f.order();
  const checkout = f.service.checkout(order);
  const business = JSON.parse(checkout.fields.biz_content);
  assert.equal(business.out_trade_no, order.orderID.replaceAll('-', ''));
  assert.match(business.time_expire, /^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/);
  assert.equal(business.timeout_express, undefined);
  assert.equal(verify('RSA-SHA256', Buffer.from(canonicalParameters(checkout.fields, false)), f.merchantKeys.publicKey, Buffer.from(checkout.fields.sign, 'base64')), true);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, priceCents: 10000000001 }), /priceCents/);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, productName: 'bad&subject' }), /productName/);
  f.close();
}
function reconciliationSafety() {
  const f = new Fixture();
  const order = f.paidOrder();
  const result = { code: '10000', out_trade_no: order.orderID.replaceAll('-', ''), trade_no: f.notification(order, {}).trade_no, total_amount: '99.00', trade_status: 'TRADE_SUCCESS' };
  assert.equal(f.service.reconcileTrade(order.orderID, result).status, 'paid');
  rejectFault(f.service.reconcileTrade(order.orderID, { ...result, trade_status: 'TRADE_CLOSED', trade_no: 'different' }), 502);
  assert.equal(f.service.orderStatus(order).status, 'paid');
  assert.equal(f.service.reconcileRefund(order.orderID, 'refund-1', { code: '10000', trade_no: result.trade_no, out_trade_no: result.out_trade_no, out_request_no: 'refund-1', refund_amount: '99.00' }).confirmed, false);
  assert.equal(f.service.orderStatus(order).status, 'paid');
  rejectFault(f.service.reconcileRefund(order.orderID, 'refund-1', { code: '10000', trade_no: 'wrong', out_trade_no: result.out_trade_no, out_request_no: 'refund-1', refund_amount: '99.00', refund_status: 'REFUND_SUCCESS' }), 502);
  assert.equal(f.service.reconcileRefund(order.orderID, 'refund-1', { code: '10000', trade_no: result.trade_no, out_trade_no: result.out_trade_no, out_request_no: 'refund-1', refund_amount: '1.00', refund_status: 'REFUND_SUCCESS' }).status, 'revoked');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  f.close();
}

test('支付宝页面支付使用合法商户单号、绝对过期时间与真实请求签名', alipayCheckoutProtocol);
test('核对交易号先于撤销，退款查询不能仅凭10000认定成功', reconciliationSafety);

function refundTimestampCannotGrant() {
  const f = new Fixture();
  const order = f.order();
  assert.equal(f.service.processNotification(f.notification(order, { gmt_refund: '2026-11-21 10:00:00' })), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  f.close();
}
function exportCrossLanguageFixture() {
  const f = new Fixture();
  const order = f.paidOrder();
  const signedLicense = f.service.activate(f.credentials(order, {}));
  const publicKey = f.licenseKeys.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
  mkdirSync(resolve('Tests/commercial-launch/fixtures'), { recursive: true });
  writeFileSync(resolve('Tests/commercial-launch/fixtures/license.json'), JSON.stringify({ publicKey, productID: f.configuration.productID, deviceID, signedLicense }, null, 2) + '\n');
  assert.equal(verify(null, Buffer.from(signedLicense.claimsData, 'base64'), f.licenseKeys.publicKey, Buffer.from(signedLicense.signature, 'base64')), true);
  f.close();
}

test('只有gmt_refund也作为退款处理，不能在旧支付状态中开通', refundTimestampCannotGrant);
if (process.env.SUPERCLEANER_EXPORT_INTEROP_FIXTURE === '1') test('输出跨语言真实服务签名夹具', exportCrossLanguageFixture);

function adminCommandsAndBackup() {
  const f = new Fixture();
  const order = f.paidOrder();
  const configPath = resolve(f.directory, 'config.json');
  const backupPath = resolve(f.directory, 'backup.sqlite');
  const proxyPath = resolve(f.directory, 'proxy.conf');
  writeFileSync(configPath, JSON.stringify(f.rawConfiguration));
  const clientConfig = spawnSync(process.execPath, ['CommerceService/admin.mjs', 'client-config', configPath], { encoding: 'utf8' });
  assert.equal(clientConfig.status, 0, clientConfig.stderr);
  assert.equal(JSON.parse(clientConfig.stdout).licensePublicKey, f.licenseKeys.publicKey.export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64'));
  const proxyConfig = spawnSync(process.execPath, ['CommerceService/admin.mjs', 'proxy-config', configPath, proxyPath], { encoding: 'utf8' });
  assert.equal(proxyConfig.status, 0, proxyConfig.stderr);
  assert.equal(proxyConfig.stdout.includes(f.proxySharedSecret), false);
  assert.equal(statSync(proxyPath).mode & 0o777, 0o600);
  assert.ok(readFileSync(proxyPath, 'utf8').includes(f.proxySharedSecret));
  const inspect = spawnSync(process.execPath, ['CommerceService/admin.mjs', 'inspect', configPath, order.orderID], { encoding: 'utf8' });
  assert.equal(inspect.status, 0, inspect.stderr);
  assert.equal(inspect.stdout.includes(order.licenseKey), false);
  assert.equal(inspect.stdout.includes(order.pollToken), false);
  const revoke = spawnSync(process.execPath, ['CommerceService/admin.mjs', 'revoke', configPath, order.orderID, '已人工核对退款凭证'], { encoding: 'utf8' });
  assert.equal(revoke.status, 0, revoke.stderr);
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  const backup = spawnSync(process.execPath, ['CommerceService/admin.mjs', 'backup', configPath, backupPath], { encoding: 'utf8' });
  assert.equal(backup.status, 0, backup.stderr);
  assert.ok(readFileSync(backupPath).length > 0);
  assert.equal(readFileSync(backupPath).includes(Buffer.from(order.licenseKey)), false);
  f.close();
}

test('服务器命令行导出公钥、核对、撤销和在线一致性备份', adminCommandsAndBackup);

function privateKeyPermissions() {
  const f = new Fixture();
  chmodSync(f.rawConfiguration.licenseEncryptionKeyPath, 0o644);
  assert.throws(validateConfiguration.bind(null, f.rawConfiguration), /权限/);
  chmodSync(f.rawConfiguration.licenseEncryptionKeyPath, 0o600);
  f.close();
}

test('启动拒绝可被其他用户读取的授权加密私钥文件', privateKeyPermissions);

function lateRefundPersistsOnClosedOrder() {
  const f = new Fixture();
  const order = f.order();
  assert.equal(f.service.processNotification(f.notification(order, { trade_status: 'TRADE_CLOSED' })), 'success');
  assert.equal(f.service.processNotification(f.notification(order, { refund_fee: '1.00' })), 'success');
  assert.equal(f.service.orderStatus(order).status, 'revoked');
  f.close();
}
function canonicalNotifyUsesDecodedValuesOnce() {
  const fields = { sign: 'excluded', b: 'x+y%z', sign_type: 'RSA2', empty: '', a: '中 文' };
  assert.equal(canonicalParameters(fields, true), 'a=中 文&b=x+y%z');
  assert.equal(canonicalParameters(fields, false), 'a=中 文&b=x+y%z&sign_type=RSA2');
}

test('关闭后到达的退款仍持久化为撤销，后续成功不会复活', lateRefundPersistsOnClosedOrder);
test('RSA2待验签按官方排序排除字段，已解码中文加号百分号只使用一次', canonicalNotifyUsesDecodedValuesOnce);

function configurationSecurityCeilings() {
  const f = new Fixture();
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, offlineLeaseSeconds: 366 * 86400 + 1 }), /offlineLeaseSeconds/);
  assert.throws(validateConfiguration.bind(null, { ...f.rawConfiguration, requestBodyLimitBytes: 1048577 }), /requestBodyLimitBytes/);
  f.close();
}
async function orderRateLimitCannotTrustForwardedAddress() {
  const f = new Fixture();
  f.service.close();
  f.configuration = validateConfiguration({ ...f.rawConfiguration, orderRateLimitMax: 2 });
  f.service = new CommerceService(f.configuration);
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  const base = `http://127.0.0.1:${server.address().port}`;
  for (let index = 0; index < 4; index += 1) {
    const response = await fetch(`${base}/v1/orders`, { method: 'POST', headers: { ...f.proxyHeaders(), 'content-type': 'application/json', 'x-forwarded-for': `198.51.100.${index}` }, body: JSON.stringify({ email, deviceID }) });
    assert.equal(response.status, index < 2 ? 200 : 429);
    if (index >= 2) assert.ok(Number(response.headers.get('retry-after')) >= 1);
  }
  assert.equal(f.service.database.prepare('SELECT COUNT(*) AS count FROM orders').get().count, 2);
  await server.close();
  f.close();
}
async function oversizeUploadRespondsBeforeUploadFinishes() {
  const f = new Fixture();
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  const headerCases = [{ ...f.proxyHeaders(), 'content-type': 'application/json', 'content-length': '1000000000' }, { ...f.proxyHeaders(), 'content-type': 'application/json' }];
  for (const headers of headerCases) {
    const request = httpRequest({ host: '127.0.0.1', port: server.address().port, path: '/v1/orders', method: 'POST', headers });
    request.write('x'.repeat(20000));
    const response = (await once(request, 'response'))[0];
    assert.equal(response.statusCode, 413);
    response.resume();
    request.destroy();
  }
  await server.close();
  f.close();
}

test('离线租约最多366天、请求体大小最多1MiB', configurationSecurityCeilings);
test('订单限流返回429和Retry-After，伪造XFF不能绕过', orderRateLimitCannotTrustForwardedAddress);
test('超大上传尚未结束就返回413并关闭连接', oversizeUploadRespondsBeforeUploadFinishes);

function pagePayContainsOnlyDocumentedBusinessFields() {
  const f = new Fixture();
  const business = JSON.parse(f.service.checkout(f.order()).fields.biz_content);
  assert.deepEqual(Object.keys(business).sort(), ['out_trade_no', 'product_code', 'total_amount', 'subject', 'time_expire'].sort());
  f.close();
}

test('网页支付只发送官方page.pay模型支持的必要业务字段', pagePayContainsOnlyDocumentedBusinessFields);

async function rawTargetStatus(f, server, target, headers) {
  const request = httpRequest({ host: '127.0.0.1', port: server.address().port, path: target, method: 'POST', headers });
  request.end(JSON.stringify({ email, deviceID }));
  const response = (await once(request, 'response'))[0];
  response.resume();
  return response.statusCode;
}
async function malformedRequestTargetsCannotCrashService() {
  const f = new Fixture();
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  const headers = { ...f.proxyHeaders(), 'content-type': 'application/json' };
  for (const target of ['//[', 'http://[', '/\\[', '/v1/orders#fragment']) assert.equal(await rawTargetStatus(f, server, target, headers), 400);
  assert.equal(await rawTargetStatus(f, server, '/v1/orders', headers), 200);
  await server.close();
  f.close();
}
async function trustedProxySeparatesClientLimitsAndRejectsForgery() {
  const f = new Fixture();
  f.service.close();
  f.configuration = validateConfiguration({ ...f.rawConfiguration, orderRateLimitMax: 2 });
  f.service = new CommerceService(f.configuration);
  const server = createHTTPServer(f.service);
  f.server = server;
  await server.listen(0, '127.0.0.1');
  for (const ip of ['198.51.100.1', '198.51.100.2']) {
    const headers = { ...f.proxyHeaders(), 'x-real-ip': ip, 'content-type': 'application/json' };
    assert.equal(await rawTargetStatus(f, server, '/v1/orders', headers), 200);
    assert.equal(await rawTargetStatus(f, server, '/v1/orders', headers), 200);
    assert.equal(await rawTargetStatus(f, server, '/v1/orders', headers), 429);
  }
  assert.equal(await rawTargetStatus(f, server, '/v1/orders', { ...f.proxyHeaders(), 'x-real-ip': '198.51.100.3', 'x-supercleaner-proxy-token': 'forged', 'content-type': 'application/json' }), 403);
  assert.equal(await rawTargetStatus(f, server, '/v1/orders', { ...f.proxyHeaders(), 'x-real-ip': 'invalid', 'content-type': 'application/json' }), 403);
  const duplicate = ['Host', '127.0.0.1', 'content-type', 'application/json', 'x-supercleaner-proxy-token', f.proxySharedSecret, 'x-real-ip', '198.51.100.4', 'x-real-ip', '198.51.100.5'];
  assert.equal(await rawTargetStatus(f, server, '/v1/orders', duplicate), 403);
  assert.equal(f.service.database.prepare('SELECT COUNT(*) AS count FROM orders').get().count, 4);
  await server.close();
  f.close();
}

test('恶意request-target返回400且下一有效请求仍成功', malformedRequestTargetsCannotCrashService);
test('可信代理分离外部IP额度并拒绝伪造或重复代理头', trustedProxySeparatesClientLimitsAndRejectsForgery);

function rateLimiterMemoryIsBoundedAndExpiredBucketsAreRemoved() {
  const f = new Fixture();
  const server = createHTTPServer(f.service);
  f.server = server;
  for (let index = 0; index < 65536; index += 1) assert.equal(server.rateLimit('/v1/orders', `2001:db8::${index.toString(16)}`), true);
  rejectFault(server.rateLimit('/v1/orders', '2001:db8:1::1'), 429);
  assert.equal(server.rateLimits.size, 65536);
  for (const bucket of server.rateLimits.values()) bucket.expires = 0;
  assert.equal(server.rateLimit('/v1/orders', '2001:db8:1::1'), true);
  assert.equal(server.rateLimits.size, 1);
  f.close();
}

test('限流计数表有内存上限且过期IP及时移除', rateLimiterMemoryIsBoundedAndExpiredBucketsAreRemoved);
