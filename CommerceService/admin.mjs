import { createPublicKey } from 'node:crypto';
import { writeFileSync } from 'node:fs';
import { isAbsolute } from 'node:path';
import { CommerceService, ServiceFault, alipayOrderNumber, loadConfiguration, signedAlipayParameters, verifyAlipayResponse } from './commerce.mjs';

async function queryAlipay(configuration, method, business) {
  const parameters = signedAlipayParameters(configuration, method, business, {});
  const response = await fetch(configuration.alipayGateway, { method: 'POST', headers: { 'content-type': 'application/x-www-form-urlencoded; charset=utf-8' }, body: new URLSearchParams(parameters).toString(), redirect: 'error', signal: AbortSignal.timeout(configuration.upstreamTimeoutMilliseconds) });
  if (!response.ok) throw new Error(`支付宝 HTTPS 网关请求失败：HTTP ${response.status}`);
  const chunks = [];
  let length = 0;
  for await (const chunk of response.body) {
    length += chunk.length;
    if (length > configuration.requestBodyLimitBytes) throw new Error('支付宝响应超过配置的大小限制');
    chunks.push(chunk);
  }
  const result = verifyAlipayResponse(Buffer.concat(chunks).toString('utf8'), method, configuration.alipayPublicKey);
  if (result instanceof ServiceFault) throw new Error(result.error);
  return result;
}

function inspectOrder(service, orderID) {
  const order = service.database.prepare('SELECT order_id AS orderID,status,price_cents AS priceCents,payment_trade_no AS tradeNo,created_at AS createdAt,revoked_reason AS revokedReason FROM orders WHERE order_id = ?').get(orderID);
  if (order === undefined) throw new Error('订单不存在');
  return order;
}

async function main() {
  const version = process.versions.node.split('.');
  if (Number(version[0]) < 24 || (Number(version[0]) === 24 && Number(version[1]) < 13)) throw new Error('管理工具需要 Node.js 24.13 或更高版本');
  const command = process.argv[2];
  if (!['check-config', 'client-config', 'proxy-config', 'inspect', 'reconcile', 'refund-query', 'revoke', 'backup'].includes(command)) throw new Error('用法：node CommerceService/admin.mjs <check-config|client-config|proxy-config|inspect|reconcile|refund-query|revoke|backup> <配置文件> [订单ID|输出绝对路径] [退款请求号|撤销原因]');
  process.umask(0o077);
  const configuration = loadConfiguration(process.argv[3]);
  if (command === 'check-config') {
    console.log(JSON.stringify({ valid: true, gateway: configuration.alipayGateway, priceCents: configuration.priceCents, deviceLimit: configuration.deviceLimit, warning: '配置格式有效不代表已获得支付权限；必须真实联调并核对商户签约状态' }));
    return;
  }
  if (command === 'client-config') {
    const publicKey = createPublicKey(configuration.licensePrivateKey).export({ type: 'spki', format: 'der' }).subarray(-32).toString('base64');
    console.log(JSON.stringify({ schemaVersion: 1, productID: configuration.productID, apiBaseURL: configuration.publicBaseURL, licensePublicKey: publicKey }, null, 2));
    return;
  }
  if (command === 'proxy-config') {
    const destination = process.argv[4];
    if (typeof destination !== 'string' || !isAbsolute(destination)) throw new Error('代理配置输出必须为尚不存在的绝对路径');
    writeFileSync(destination, `proxy_set_header X-SuperCleaner-Proxy-Token "${configuration.proxySharedSecret}";\n`, { mode: 0o600, flag: 'wx' });
    console.log(JSON.stringify({ written: true, path: destination, warning: '该代理配置含共享密钥，必须保持私有，不可放入公开仓库或日志' }));
    return;
  }
  const service = new CommerceService(configuration);
  const argument = process.argv[4];
  let result;
  switch (command) {
    case 'inspect': result = inspectOrder(service, argument); break;
    case 'revoke': result = service.revokeOrder(argument, process.argv[5]); break;
    case 'reconcile': {
      inspectOrder(service, argument);
      const query = await queryAlipay(configuration, 'alipay.trade.query', { out_trade_no: alipayOrderNumber(argument) });
      result = service.reconcileTrade(argument, query);
      break;
    }
    case 'refund-query': {
      inspectOrder(service, argument);
      const requestID = process.argv[5];
      if (typeof requestID !== 'string' || !/^[A-Za-z0-9_-]{1,64}$/.test(requestID)) throw new Error('退款查询必须提供原始退款请求号，不得生成新号冒充原请求');
      const query = await queryAlipay(configuration, 'alipay.trade.fastpay.refund.query', { out_trade_no: alipayOrderNumber(argument), out_request_no: requestID });
      result = service.reconcileRefund(argument, requestID, query);
      break;
    }
    case 'backup': {
      if (typeof argument !== 'string' || !isAbsolute(argument)) throw new Error('备份路径必须为绝对路径');
      service.database.prepare('VACUUM INTO ?').run(argument);
      result = { backedUp: true, path: argument, warning: '还需在独立安全位置备份授权加密密钥、签名密钥和配置；不要将密钥放入公开备份' };
      break;
    }
  }
  service.close();
  if (result instanceof ServiceFault) throw new Error(result.error);
  console.log(JSON.stringify(result, null, 2));
}

await main();
