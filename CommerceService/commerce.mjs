import { createCipheriv, createDecipheriv, createHash, createPrivateKey, createPublicKey, randomBytes, randomUUID, sign, timingSafeEqual, verify } from 'node:crypto';
import { readFileSync, statSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { DatabaseSync } from 'node:sqlite';

const configurationFields = ['schemaVersion', 'host', 'port', 'publicBaseURL', 'productID', 'productName', 'priceCents', 'deviceLimit', 'offlineLeaseSeconds', 'orderTTLSeconds', 'rateLimitWindowSeconds', 'requestRateLimitMax', 'orderRateLimitMax', 'requestBodyLimitBytes', 'requestTimeoutMilliseconds', 'upstreamTimeoutMilliseconds', 'alipayGateway', 'alipayAppID', 'alipaySellerID', 'alipayPrivateKeyPath', 'alipayPublicKeyPath', 'licensePrivateKeyPath', 'licenseEncryptionKeyPath', 'proxySharedSecretPath', 'databasePath'];
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[1-8][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}$/i;
const allowedGateways = ['https://openapi.alipay.com/gateway.do', 'https://openapi-sandbox.dl.alipaydev.com/gateway.do'];

export class ServiceFault {
  constructor(status, error) { this.status = status; this.error = error; }
}

export function validateConfiguration(raw) {
  if (raw === null || typeof raw !== 'object' || Array.isArray(raw)) throw new Error('配置必须是 JSON 对象');
  for (const key of Object.keys(raw)) if (!configurationFields.includes(key)) throw new Error(`未知配置字段：${key}`);
  for (const key of configurationFields) if (raw[key] === undefined || raw[key] === null || raw[key] === '') throw new Error(`缺少必需配置：${key}`);
  if (raw.schemaVersion !== 1) throw new Error('schemaVersion 必须为 1');
  if (raw.host !== '127.0.0.1' && raw.host !== '::1') throw new Error('host 必须绑定本机回环地址，外部 HTTPS 由反向代理提供');
  for (const key of ['port', 'priceCents', 'deviceLimit', 'offlineLeaseSeconds', 'orderTTLSeconds', 'rateLimitWindowSeconds', 'requestRateLimitMax', 'orderRateLimitMax', 'requestBodyLimitBytes', 'requestTimeoutMilliseconds', 'upstreamTimeoutMilliseconds']) {
    if (!Number.isSafeInteger(raw[key]) || raw[key] <= 0) throw new Error(`${key} 必须为正安全整数，不提供默认值`);
  }
  if (raw.orderTTLSeconds < 60 || raw.orderTTLSeconds > 1296000) throw new Error('orderTTLSeconds 必须在 60 至 1296000 秒之间，符合支付宝 1 分钟至 15 天限制');
  if (raw.offlineLeaseSeconds > 366 * 86400) throw new Error('offlineLeaseSeconds 不得超过 366 天');
  for (const key of ['requestTimeoutMilliseconds', 'upstreamTimeoutMilliseconds']) if (raw[key] > 2147483647) throw new Error(`${key} 超过 Node 定时器范围`);
  if (raw.requestBodyLimitBytes > 1048576) throw new Error('requestBodyLimitBytes 不得超过 1 MiB');
  if (raw.rateLimitWindowSeconds > 86400) throw new Error('rateLimitWindowSeconds 不得超过 86400 秒');
  if (raw.orderRateLimitMax > raw.requestRateLimitMax) throw new Error('orderRateLimitMax 不得超过 requestRateLimitMax');
  if (raw.port > 65535) throw new Error('port 必须不超过 65535');
  if (raw.priceCents > 10000000000) throw new Error('priceCents 超过支付宝金额范围');
  if (typeof raw.publicBaseURL !== 'string' || !/^https:\/\/[^/?#]+$/.test(raw.publicBaseURL)) throw new Error('publicBaseURL 必须为无路径、查询和片段的 HTTPS 源');
  const publicURL = new URL(raw.publicBaseURL);
  if (publicURL.username || publicURL.password || publicURL.origin !== raw.publicBaseURL) throw new Error('publicBaseURL 必须为规范 HTTPS 源');
  if (!allowedGateways.includes(raw.alipayGateway)) throw new Error('alipayGateway 必须为明确的支付宝生产或沙箱 HTTPS 网关');
  for (const key of ['alipayAppID', 'alipaySellerID']) if (typeof raw[key] !== 'string' || !/^\d{16}$/.test(raw[key])) throw new Error(`${key} 必须为支付宝提供的 16 位标识，个人收款账号不能替代`);
  if (typeof raw.productID !== 'string' || !/^[A-Za-z0-9][A-Za-z0-9._-]{0,127}$/.test(raw.productID)) throw new Error('productID 格式无效');
  if (typeof raw.productName !== 'string' || raw.productName.trim().length === 0 || raw.productName.length > 128 || /[\x00-\x1f/=&]/.test(raw.productName)) throw new Error('productName 格式无效');
  for (const key of ['alipayPrivateKeyPath', 'alipayPublicKeyPath', 'licensePrivateKeyPath', 'licenseEncryptionKeyPath', 'proxySharedSecretPath', 'databasePath']) if (typeof raw[key] !== 'string' || !isAbsolute(raw[key])) throw new Error(`${key} 必须为绝对路径`);
  for (const key of ['alipayPrivateKeyPath', 'licensePrivateKeyPath', 'licenseEncryptionKeyPath', 'proxySharedSecretPath']) if ((statSync(raw[key]).mode & 0o077) !== 0) throw new Error(`${key} 文件权限不安全，必须禁止组和其他用户访问`);
  const alipayPrivateKey = createPrivateKey(readFileSync(raw.alipayPrivateKeyPath));
  const alipayPublicKey = createPublicKey(readFileSync(raw.alipayPublicKeyPath));
  const licensePrivateKey = createPrivateKey(readFileSync(raw.licensePrivateKeyPath));
  if (alipayPrivateKey.asymmetricKeyType !== 'rsa' || alipayPrivateKey.asymmetricKeyDetails.modulusLength < 2048) throw new Error('支付宝应用私钥必须为至少 2048 bit RSA');
  if (alipayPublicKey.asymmetricKeyType !== 'rsa' || alipayPublicKey.asymmetricKeyDetails.modulusLength < 2048) throw new Error('支付宝公钥必须为至少 2048 bit RSA');
  if (licensePrivateKey.asymmetricKeyType !== 'ed25519') throw new Error('授权私钥必须为 Ed25519');
  const licenseEncryptionKey = readFileSync(raw.licenseEncryptionKeyPath);
  if (licenseEncryptionKey.length !== 32) throw new Error('licenseEncryptionKeyPath 文件必须为 32 字节原始随机密钥');
  const proxySharedSecretBytes = readFileSync(raw.proxySharedSecretPath);
  if (proxySharedSecretBytes.length !== 32) throw new Error('proxySharedSecretPath 文件必须为 32 字节原始随机密钥');
  const proxySharedSecret = proxySharedSecretBytes.toString('base64url');
  return Object.freeze({ ...raw, alipayPrivateKey, alipayPublicKey, licensePrivateKey, licenseEncryptionKey, proxySharedSecret });
}

export function loadConfiguration(path) {
  if (typeof path !== 'string' || path.length === 0) throw new Error('必须指定配置文件路径');
  return validateConfiguration(JSON.parse(readFileSync(path, 'utf8')));
}

export function canonicalParameters(fields, notification) {
  const pairs = [];
  for (const key of Object.keys(fields).sort()) {
    if (key === 'sign' || (notification && key === 'sign_type') || fields[key] === '') continue;
    pairs.push(`${key}=${fields[key]}`);
  }
  return pairs.join('&');
}

function digest(value) { return createHash('sha256').update(value, 'utf8').digest(); }
function nowSeconds() { return Math.floor(Date.now() / 1000); }
function validEmail(value) { return typeof value === 'string' && value.length <= 254 && /^[^\s@]+@[^\s@]+\.[^\s@]+$/.test(value); }
function validUUID(value) { return typeof value === 'string' && uuidPattern.test(value); }
function normalizedEmail(value) { return value.trim().toLowerCase(); }
function moneyCents(value) {
  if (typeof value !== 'string' || !/^(0|[1-9]\d{0,8})(\.\d{1,2})?$/.test(value)) return null;
  const parts = value.split('.');
  return Number(parts[0]) * 100 + Number((parts[1] === undefined ? '' : parts[1]).padEnd(2, '0'));
}
function decimalMoney(cents) { return `${Math.floor(cents / 100)}.${String(cents % 100).padStart(2, '0')}`; }
function encodedSecret(value, orderID, key) {
  const nonce = randomBytes(12);
  const cipher = createCipheriv('aes-256-gcm', key, nonce);
  cipher.setAAD(Buffer.from(orderID));
  const ciphertext = Buffer.concat([cipher.update(value, 'utf8'), cipher.final()]);
  return [nonce.toString('base64'), cipher.getAuthTag().toString('base64'), ciphertext.toString('base64')].join('.');
}
function decodedSecret(value, orderID, key) {
  const parts = value.split('.');
  const decipher = createDecipheriv('aes-256-gcm', key, Buffer.from(parts[0], 'base64'));
  decipher.setAAD(Buffer.from(orderID));
  decipher.setAuthTag(Buffer.from(parts[1], 'base64'));
  return Buffer.concat([decipher.update(Buffer.from(parts[2], 'base64')), decipher.final()]).toString('utf8');
}
function alipayTimestamp(timestamp) { return new Date(timestamp + 8 * 3600000).toISOString().slice(0, 19).replace('T', ' '); }

export function alipayOrderNumber(orderID) { return orderID.replaceAll('-', '').toLowerCase(); }
function internalOrderID(value) {
  if (typeof value !== 'string' || !/^[0-9a-f]{32}$/.test(value)) return null;
  const orderID = `${value.slice(0, 8)}-${value.slice(8, 12)}-${value.slice(12, 16)}-${value.slice(16, 20)}-${value.slice(20)}`;
  return validUUID(orderID) ? orderID : null;
}

export function signedAlipayParameters(configuration, method, business, extra) {
  const fields = { app_id: configuration.alipayAppID, method, format: 'JSON', charset: 'utf-8', sign_type: 'RSA2', timestamp: alipayTimestamp(Date.now()), version: '1.0', biz_content: JSON.stringify(business), ...extra };
  fields.sign = sign('RSA-SHA256', Buffer.from(canonicalParameters(fields, false)), configuration.alipayPrivateKey).toString('base64');
  return fields;
}

// 从响应顶层提取原始对象字节，绝不重新序列化支付宝待验签 JSON。
function rawResponseValue(text, name) {
  const marker = `"${name}"`;
  let position = 0;
  let level = 0;
  let inString = false;
  let escaped = false;
  let start = -1;
  while (position < text.length) {
    const character = text[position];
    if (inString) {
      if (escaped) escaped = false;
      else if (character === '\\') escaped = true;
      else if (character === '"') inString = false;
    } else if (character === '"') {
      if (level === 1 && text.startsWith(marker, position)) {
        let next = position + marker.length;
        while (/\s/.test(text[next]) && next < text.length) next += 1;
        if (text[next] !== ':') return null;
        next += 1;
        while (/\s/.test(text[next]) && next < text.length) next += 1;
        if (text[next] !== '{' || start !== -1) return null;
        start = next;
      }
      inString = true;
    } else if (character === '{' || character === '[') level += 1;
    else if (character === '}' || character === ']') {
      level -= 1;
      if (start !== -1 && level === 1) return text.slice(start, position + 1);
    }
    position += 1;
  }
  return null;
}

export function verifyAlipayResponse(text, method, publicKey) {
  const responseKey = `${method.replaceAll('.', '_')}_response`;
  const raw = rawResponseValue(text, responseKey);
  if (raw === null) return new ServiceFault(502, '支付宝响应缺少待验签业务对象');
  const envelope = JSON.parse(text);
  if (typeof envelope.sign !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(envelope.sign)) return new ServiceFault(502, '支付宝响应缺少有效签名');
  if (!verify('RSA-SHA256', Buffer.from(raw), publicKey, Buffer.from(envelope.sign, 'base64'))) return new ServiceFault(502, '支付宝响应签名验证失败');
  return JSON.parse(raw);
}

export class CommerceService {
  constructor(configuration) {
    this.configuration = configuration;
    this.database = new DatabaseSync(configuration.databasePath);
    this.database.exec(`PRAGMA journal_mode = WAL; PRAGMA foreign_keys = ON; PRAGMA busy_timeout = ${configuration.requestTimeoutMilliseconds};
      CREATE TABLE IF NOT EXISTS orders (
        order_id TEXT PRIMARY KEY, email TEXT NOT NULL, device_id TEXT NOT NULL,
        price_cents INTEGER NOT NULL CHECK(price_cents > 0), poll_token_hash BLOB NOT NULL,
        created_at INTEGER NOT NULL, expires_at INTEGER NOT NULL,
        status TEXT NOT NULL CHECK(status IN ('pending','paid','revoked','closed')),
        payment_trade_no TEXT UNIQUE, license_id TEXT, revoked_reason TEXT);
      CREATE TABLE IF NOT EXISTS licenses (
        license_id TEXT PRIMARY KEY, order_id TEXT NOT NULL UNIQUE REFERENCES orders(order_id), email TEXT NOT NULL,
        key_hash BLOB NOT NULL UNIQUE, key_cipher TEXT NOT NULL, created_at INTEGER NOT NULL, revoked_at INTEGER);
      CREATE TABLE IF NOT EXISTS devices (
        license_id TEXT NOT NULL REFERENCES licenses(license_id), device_id TEXT NOT NULL, device_name TEXT NOT NULL,
        activated_at INTEGER NOT NULL, deactivated_at INTEGER, PRIMARY KEY(license_id,device_id));
      CREATE TABLE IF NOT EXISTS audit_events (
        id INTEGER PRIMARY KEY, event TEXT NOT NULL, order_id TEXT NOT NULL REFERENCES orders(order_id), created_at INTEGER NOT NULL, detail TEXT NOT NULL);`);
  }
  close() { this.database.close(); }
  rollback(fault) { this.database.exec('ROLLBACK'); return fault; }
  audit(event, orderID, detail) { this.database.prepare('INSERT INTO audit_events(event,order_id,created_at,detail) VALUES(?,?,?,?)').run(event, orderID, nowSeconds(), detail); }
  createOrder(input) {
    if (!validEmail(input.email) || !validUUID(input.deviceID)) return new ServiceFault(400, '请输入有效邮箱和设备 UUID');
    const orderID = randomUUID();
    const pollToken = randomBytes(32).toString('base64url');
    const timestamp = nowSeconds();
    this.database.prepare("INSERT INTO orders(order_id,email,device_id,price_cents,poll_token_hash,created_at,expires_at,status) VALUES(?,?,?,?,?,?,?,'pending')").run(orderID, normalizedEmail(input.email), input.deviceID.toLowerCase(), this.configuration.priceCents, digest(pollToken), timestamp, timestamp + this.configuration.orderTTLSeconds);
    return { orderID, pollToken, checkoutURL: `${this.configuration.publicBaseURL}/checkout/${orderID}?token=${pollToken}` };
  }
  authorizedOrder(input) {
    if (!validUUID(input.orderID) || typeof input.pollToken !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(input.pollToken)) return new ServiceFault(403, '订单或购买凭证无效');
    const order = this.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(input.orderID.toLowerCase());
    if (order === undefined || !timingSafeEqual(digest(input.pollToken), Buffer.from(order.poll_token_hash))) return new ServiceFault(403, '订单或购买凭证无效');
    return order;
  }
  orderStatus(input) {
    const order = this.authorizedOrder(input);
    if (order instanceof ServiceFault) return order;
    if (order.status !== 'paid') return { status: order.status, licenseKey: null };
    const license = this.database.prepare('SELECT key_cipher FROM licenses WHERE license_id = ? AND revoked_at IS NULL').get(order.license_id);
    if (license === undefined) throw new Error('已付款订单缺少有效授权，数据库完整性错误');
    return { status: 'paid', licenseKey: decodedSecret(license.key_cipher, order.order_id, this.configuration.licenseEncryptionKey) };
  }
  checkout(input) {
    const order = this.authorizedOrder(input);
    if (order instanceof ServiceFault) return order;
    if (order.status !== 'pending') return new ServiceFault(409, '订单已处理，请回到 SuperCleaner 查询状态');
    if (order.expires_at - nowSeconds() < 60) return new ServiceFault(410, '结账链接已过期，请创建新订单；已完成支付请联系商家核对');
    const fields = signedAlipayParameters(this.configuration, 'alipay.trade.page.pay', { out_trade_no: alipayOrderNumber(order.order_id), product_code: 'FAST_INSTANT_TRADE_PAY', total_amount: decimalMoney(order.price_cents), subject: this.configuration.productName, time_expire: alipayTimestamp(order.expires_at * 1000) }, { notify_url: `${this.configuration.publicBaseURL}/v1/alipay/notify` });
    return { fields, gateway: this.configuration.alipayGateway, productName: this.configuration.productName, price: decimalMoney(order.price_cents), deviceLimit: this.configuration.deviceLimit, offlineLeaseSeconds: this.configuration.offlineLeaseSeconds };
  }
  processNotification(fields) {
    if (fields === null || typeof fields !== 'object' || Array.isArray(fields)) return new ServiceFault(400, '通知参数无效');
    for (const key of Object.keys(fields)) if (typeof fields[key] !== 'string') return new ServiceFault(400, '通知参数必须是字符串');
    if (fields.sign_type !== 'RSA2' || fields.charset?.toLowerCase() !== 'utf-8' || typeof fields.sign !== 'string' || !/^[A-Za-z0-9+/]+={0,2}$/.test(fields.sign)) return new ServiceFault(400, '仅接受 UTF-8 RSA2 支付宝通知');
    if (!verify('RSA-SHA256', Buffer.from(canonicalParameters(fields, true)), this.configuration.alipayPublicKey, Buffer.from(fields.sign, 'base64'))) return new ServiceFault(400, '支付宝通知签名验证失败');
    if (fields.app_id !== this.configuration.alipayAppID || fields.seller_id !== this.configuration.alipaySellerID) return new ServiceFault(400, '支付宝应用或收款商户不匹配');
    if (internalOrderID(fields.out_trade_no) === null || typeof fields.trade_no !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(fields.trade_no)) return new ServiceFault(400, '支付宝订单号或交易号无效');
    if (!['WAIT_BUYER_PAY', 'TRADE_SUCCESS', 'TRADE_FINISHED', 'TRADE_CLOSED'].includes(fields.trade_status)) return new ServiceFault(400, '未知支付宝交易状态');
    const amount = moneyCents(fields.total_amount);
    const refund = fields.refund_fee === undefined ? 0 : moneyCents(fields.refund_fee);
    if (fields.gmt_refund !== undefined && !/^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}$/.test(fields.gmt_refund)) return new ServiceFault(400, '支付宝退款时间格式无效');
    const refunded = refund > 0 || fields.gmt_refund !== undefined;
    if (amount === null || refund === null || refund > amount) return new ServiceFault(400, '支付宝金额格式无效');
    this.database.exec('BEGIN IMMEDIATE');
    const order = this.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(internalOrderID(fields.out_trade_no));
    if (order === undefined || amount !== order.price_cents) return this.rollback(new ServiceFault(400, '订单不存在或金额不匹配'));
    const existingTrade = this.database.prepare('SELECT order_id FROM orders WHERE payment_trade_no = ?').get(fields.trade_no);
    if ((existingTrade !== undefined && existingTrade.order_id !== order.order_id) || (order.payment_trade_no !== null && order.payment_trade_no !== fields.trade_no)) return this.rollback(new ServiceFault(400, '支付宝交易号不匹配或已绑定其它订单'));
    this.database.prepare('UPDATE orders SET payment_trade_no = ? WHERE order_id = ?').run(fields.trade_no, order.order_id);
    if (order.status === 'revoked' || (order.status === 'closed' && !refunded)) {
      this.database.exec('COMMIT');
      return 'success';
    }
    if (refunded || fields.trade_status === 'TRADE_CLOSED') {
      const status = refunded || order.status === 'paid' ? 'revoked' : 'closed';
      this.database.prepare('UPDATE orders SET status = ?, revoked_reason = ? WHERE order_id = ?').run(status, '支付宝已退款或关闭交易', order.order_id);
      this.database.prepare('UPDATE licenses SET revoked_at = ? WHERE order_id = ? AND revoked_at IS NULL').run(nowSeconds(), order.order_id);
      this.audit(status, order.order_id, '已验签支付宝交易变更');
    } else if (['TRADE_SUCCESS', 'TRADE_FINISHED'].includes(fields.trade_status) && order.status === 'pending') {
      const licenseID = randomUUID();
      const licenseKey = randomBytes(32).toString('base64url');
      this.database.prepare('INSERT INTO licenses(license_id,order_id,email,key_hash,key_cipher,created_at) VALUES(?,?,?,?,?,?)').run(licenseID, order.order_id, order.email, digest(licenseKey), encodedSecret(licenseKey, order.order_id, this.configuration.licenseEncryptionKey), nowSeconds());
      this.database.prepare("UPDATE orders SET status = 'paid', license_id = ? WHERE order_id = ?").run(licenseID, order.order_id);
      this.audit('paid', order.order_id, '已验签支付宝支付成功');
    }
    this.database.exec('COMMIT');
    return 'success';
  }
  authenticatedLicense(input) {
    if (!validEmail(input.email) || typeof input.licenseKey !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(input.licenseKey)) return new ServiceFault(403, '邮箱或激活码无效');
    const license = this.database.prepare('SELECT * FROM licenses WHERE key_hash = ? AND email = ?').get(digest(input.licenseKey), normalizedEmail(input.email));
    if (license === undefined || license.revoked_at !== null) return new ServiceFault(403, '授权无效或已撤销');
    return license;
  }
  lease(license, deviceID) {
    const issuedAt = nowSeconds();
    const claims = { licenseID: license.license_id, productID: this.configuration.productID, email: license.email, deviceID, issuedAt, offlineValidUntil: issuedAt + this.configuration.offlineLeaseSeconds, capabilities: ['standardScan', 'agentScan', 'newCleanup'] };
    const data = Buffer.from(JSON.stringify(claims), 'utf8');
    return { claimsData: data.toString('base64'), signature: sign(null, data, this.configuration.licensePrivateKey).toString('base64') };
  }
  activate(input) {
    if (!validUUID(input.deviceID) || typeof input.deviceName !== 'string' || input.deviceName.trim().length === 0 || input.deviceName.length > 128 || /[\x00-\x1f]/.test(input.deviceName)) return new ServiceFault(400, '设备 UUID 或名称无效');
    this.database.exec('BEGIN IMMEDIATE');
    const license = this.authenticatedLicense(input);
    if (license instanceof ServiceFault) return this.rollback(license);
    const id = input.deviceID.toLowerCase();
    const device = this.database.prepare('SELECT * FROM devices WHERE license_id = ? AND device_id = ?').get(license.license_id, id);
    if (device === undefined || device.deactivated_at !== null) {
      const active = this.database.prepare('SELECT COUNT(*) AS count FROM devices WHERE license_id = ? AND deactivated_at IS NULL').get(license.license_id);
      if (active.count >= this.configuration.deviceLimit) return this.rollback(new ServiceFault(409, '已达到设备上限，请先解绑旧设备'));
      this.database.prepare('INSERT INTO devices(license_id,device_id,device_name,activated_at,deactivated_at) VALUES(?,?,?,?,NULL) ON CONFLICT(license_id,device_id) DO UPDATE SET device_name = excluded.device_name, activated_at = excluded.activated_at, deactivated_at = NULL').run(license.license_id, id, input.deviceName.trim(), nowSeconds());
      this.audit('activated', license.order_id, id);
    }
    const signed = this.lease(license, id);
    this.database.exec('COMMIT');
    return signed;
  }
  refresh(input) {
    if (!validUUID(input.deviceID) || typeof input.deviceName !== 'string' || input.deviceName.trim().length === 0 || input.deviceName.length > 128 || /[\x00-\x1f]/.test(input.deviceName)) return new ServiceFault(400, '设备 UUID 或名称无效');
    this.database.exec('BEGIN IMMEDIATE');
    const license = this.authenticatedLicense(input);
    if (license instanceof ServiceFault) return this.rollback(license);
    const id = input.deviceID.toLowerCase();
    const device = this.database.prepare('SELECT * FROM devices WHERE license_id = ? AND device_id = ? AND deactivated_at IS NULL').get(license.license_id, id);
    if (device === undefined) return this.rollback(new ServiceFault(403, '此设备未激活或已经解绑，请显式激活'));
    const signed = this.lease(license, id);
    this.database.exec('COMMIT');
    return signed;
  }
  devices(input) {
    const license = this.authenticatedLicense(input);
    if (license instanceof ServiceFault) return license;
    return { devices: this.database.prepare('SELECT device_id AS deviceID, device_name AS deviceName, activated_at AS activatedAt FROM devices WHERE license_id = ? AND deactivated_at IS NULL ORDER BY activated_at, device_id').all(license.license_id) };
  }
  deactivate(input) {
    if (!validUUID(input.deviceID)) return new ServiceFault(400, '设备 UUID 无效');
    this.database.exec('BEGIN IMMEDIATE');
    const license = this.authenticatedLicense(input);
    if (license instanceof ServiceFault) return this.rollback(license);
    const updated = this.database.prepare('UPDATE devices SET deactivated_at = ? WHERE license_id = ? AND device_id = ? AND deactivated_at IS NULL').run(nowSeconds(), license.license_id, input.deviceID.toLowerCase());
    if (updated.changes > 0) this.audit('deactivated', license.order_id, input.deviceID.toLowerCase());
    this.database.exec('COMMIT');
    return { deactivated: true };
  }
  revokeOrder(orderID, reason) {
    if (!validUUID(orderID) || typeof reason !== 'string' || reason.trim().length === 0 || reason.length > 512) return new ServiceFault(400, '撤销需要订单 UUID 和明确原因');
    this.database.exec('BEGIN IMMEDIATE');
    const order = this.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(orderID.toLowerCase());
    if (order === undefined) return this.rollback(new ServiceFault(404, '订单不存在'));
    this.database.prepare("UPDATE orders SET status = 'revoked', revoked_reason = ? WHERE order_id = ?").run(reason, order.order_id);
    this.database.prepare('UPDATE licenses SET revoked_at = ? WHERE order_id = ? AND revoked_at IS NULL').run(nowSeconds(), order.order_id);
    this.audit('admin-revoked', order.order_id, reason);
    this.database.exec('COMMIT');
    return { status: 'revoked' };
  }
  reconcileTrade(orderID, result) {
    const order = this.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(orderID);
    if (order === undefined) return new ServiceFault(404, '订单不存在');
    if (result.code !== '10000') return new ServiceFault(502, '支付宝查询未成功，必须人工核对，不修改授权');
    if (result.out_trade_no !== alipayOrderNumber(orderID) || typeof result.trade_no !== 'string' || moneyCents(result.total_amount) !== order.price_cents) return new ServiceFault(502, '支付宝核对的订单、金额或交易号不匹配');
    if (order.payment_trade_no !== null && order.payment_trade_no !== result.trade_no) return new ServiceFault(502, '支付宝核对交易号与已记录交易不符');
    if (!['WAIT_BUYER_PAY', 'TRADE_SUCCESS', 'TRADE_FINISHED', 'TRADE_CLOSED'].includes(result.trade_status)) return new ServiceFault(502, '支付宝查询交易状态无效');
    // 交易查询不保证返回 seller_id；它只核对，不代替完整商户异步通知开通授权。
    if (result.trade_status === 'TRADE_CLOSED' && order.payment_trade_no !== null) return this.revokeOrder(orderID, '已验签支付宝交易核对显示关闭');
    return { status: order.status, tradeStatus: result.trade_status, requiresNotificationOrManualReview: order.status === 'pending' && result.trade_status !== 'WAIT_BUYER_PAY' };
  }
  reconcileRefund(orderID, requestID, result) {
    const order = this.database.prepare('SELECT * FROM orders WHERE order_id = ?').get(orderID);
    if (order === undefined) return new ServiceFault(404, '订单不存在');
    if (result.code !== '10000') return new ServiceFault(502, '支付宝退款查询未成功，不修改授权');
    if (result.refund_status !== 'REFUND_SUCCESS') return { status: order.status, confirmed: false, requiresManualReview: true };
    const refund = moneyCents(result.refund_amount);
    if (order.payment_trade_no === null || result.trade_no !== order.payment_trade_no || result.out_trade_no !== alipayOrderNumber(orderID) || result.out_request_no !== requestID || refund === null || refund <= 0 || refund > order.price_cents) return new ServiceFault(502, '支付宝退款查询订单、交易号、退款请求号或金额不匹配');
    return this.revokeOrder(orderID, `已验签退款查询确认成功：${requestID}`);
  }
}
