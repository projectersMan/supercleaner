import { once } from 'node:events';
import { createServer } from 'node:http';
import { timingSafeEqual } from 'node:crypto';
import { isIP } from 'node:net';
import { performance } from 'node:perf_hooks';
import { CommerceService, ServiceFault } from './commerce.mjs';

function escapeHTML(value) { return String(value).replaceAll('&', '&amp;').replaceAll('<', '&lt;').replaceAll('>', '&gt;').replaceAll('"', '&quot;').replaceAll("'", '&#39;'); }
function displayDuration(seconds) {
  if (seconds % 86400 === 0) return `${seconds / 86400}天`;
  if (seconds % 3600 === 0) return `${seconds / 3600}小时`;
  return `${Math.ceil(seconds / 60)}分钟`;
}

function checkoutHTML(checkout) {
  const fields = [];
  for (const key of Object.keys(checkout.fields)) fields.push(`<input type="hidden" name="${escapeHTML(key)}" value="${escapeHTML(checkout.fields[key])}">`);
  const duration = displayDuration(checkout.offlineLeaseSeconds);
  return `<!doctype html><html lang="zh-CN"><meta charset="utf-8"><meta name="viewport" content="width=device-width, initial-scale=1"><title>SuperCleaner 安全结账</title><main><h1>${escapeHTML(checkout.productName)}</h1><p>一次性支付人民币 ${escapeHTML(checkout.price)} 元，买断权益永久有效，可激活 ${checkout.deviceLimit} 台设备。</p><p>设备离线授权有效期为${duration}。到期联网刷新；退款或解绑后，离线授权最迟在${duration}内失效。</p><p>支付结果由服务端核验。完成后请返回 SuperCleaner 查询并领取激活码。浏览器跳转不会开通授权。</p><form method="post" action="${escapeHTML(checkout.gateway)}" accept-charset="UTF-8">${fields.join('')}<button type="submit">前往支付宝支付</button></form><p>请勿分享结账链接或激活码。官方分发与配套授权服务收费；项目源码继续遵循 GPL v3。</p></main></html>`;
}

class RequestBody {
  constructor(request, limit) {
    this.request = request;
    this.limit = limit;
    this.length = 0;
    this.chunks = [];
    this.finished = false;
    this.promise = new Promise(this.initialize.bind(this));
  }
  initialize(resolve, reject) {
    this.resolve = resolve;
    this.reject = reject;
    this.request.on('data', this.data.bind(this));
    this.request.on('end', this.end.bind(this));
    this.request.on('aborted', this.aborted.bind(this));
    this.request.on('error', this.error.bind(this));
  }
  data(chunk) {
    if (this.finished) return;
    this.length += chunk.length;
    if (this.length > this.limit) {
      this.finished = true;
      this.chunks = [];
      this.request.pause();
      this.resolve(new ServiceFault(413, '请求内容超过大小限制'));
      return;
    }
    this.chunks.push(chunk);
  }
  end() {
    if (this.finished) return;
    this.finished = true;
    this.resolve(Buffer.concat(this.chunks).toString('utf8'));
  }
  aborted() {
    if (this.finished) return;
    this.finished = true;
    this.resolve(new ServiceFault(400, '请求传输中断'));
  }
  error(error) {
    if (error.code === 'ECONNRESET') { this.aborted(); return; }
    if (this.finished) throw error;
    this.finished = true;
    this.reject(error);
  }
}

class HTTPRequest {
  constructor(service, request, response, admission) { this.service = service; this.request = request; this.response = response; this.admission = admission; }
  start() { this.run().then(this.complete.bind(this), this.fail.bind(this)); }
  async run() {
    const request = this.request;
    const configuration = this.service.configuration;
    if (typeof request.url !== 'string' || !request.url.startsWith('/') || request.url.startsWith('//') || /[\\\x00-\x20\x7f#]/.test(request.url)) return new ServiceFault(400, '仅接受有效的 origin-form 请求路径');
    const clientAddress = this.admission.authenticatedClientAddress(request);
    if (clientAddress instanceof ServiceFault) return clientAddress;
    if (request.headers.origin !== undefined && request.headers.origin !== configuration.publicBaseURL) return new ServiceFault(403, '拒绝跨源访问购买凭证');
    if (request.headers['sec-fetch-site'] === 'cross-site' && !request.url.startsWith('/checkout/')) return new ServiceFault(403, '拒绝跨站业务请求');
    const url = new URL(request.url, configuration.publicBaseURL);
    const admitted = this.admission.rateLimit(url.pathname, clientAddress);
    if (admitted instanceof ServiceFault) return admitted;
    if (request.method === 'GET' && url.pathname.startsWith('/checkout/')) {
      if (url.searchParams.getAll('token').length !== 1 || url.searchParams.size !== 1) return new ServiceFault(403, '订单或购买凭证无效');
      const result = this.service.checkout({ orderID: url.pathname.slice('/checkout/'.length), pollToken: url.searchParams.get('token') });
      if (result instanceof ServiceFault) return result;
      return { html: checkoutHTML(result) };
    }
    if (request.method !== 'POST' || url.search.length > 0) return new ServiceFault(404, '接口不存在');
    const notification = url.pathname === '/v1/alipay/notify';
    const contentType = request.headers['content-type'];
    const requiredType = notification ? 'application/x-www-form-urlencoded' : 'application/json';
    if (typeof contentType !== 'string' || contentType.split(';')[0].trim().toLowerCase() !== requiredType) return new ServiceFault(415, `Content-Type 必须为 ${requiredType}`);
    const contentLength = request.headers['content-length'];
    if (contentLength !== undefined && (!/^\d+$/.test(contentLength) || Number(contentLength) > configuration.requestBodyLimitBytes)) return new ServiceFault(413, '请求内容超过大小限制');
    const text = await new RequestBody(request, configuration.requestBodyLimitBytes).promise;
    if (text instanceof ServiceFault) return text;
    if (notification) {
      const parameters = new URLSearchParams(text);
      const fields = Object.create(null);
      for (const [key, value] of parameters) {
        if (fields[key] !== undefined) return new ServiceFault(400, '支付宝通知包含重复字段');
        fields[key] = value;
      }
      const result = this.service.processNotification(fields);
      if (result instanceof ServiceFault) return result;
      return { text: result };
    }
    const input = JSON.parse(text);
    if (input === null || typeof input !== 'object' || Array.isArray(input)) return new ServiceFault(400, '请求内容必须为 JSON 对象');
    switch (url.pathname) {
      case '/v1/orders': return this.service.createOrder(input);
      case '/v1/orders/status': return this.service.orderStatus(input);
      case '/v1/licenses/activate': return this.service.activate(input);
      case '/v1/licenses/refresh': return this.service.refresh(input);
      case '/v1/licenses/devices': return this.service.devices(input);
      case '/v1/licenses/deactivate': return this.service.deactivate(input);
      default: return new ServiceFault(404, '接口不存在');
    }
  }
  complete(result) {
    const response = this.response;
    if (response.destroyed) return;
    response.setHeader('cache-control', 'no-store');
    response.setHeader('referrer-policy', 'no-referrer');
    response.setHeader('x-content-type-options', 'nosniff');
    response.setHeader('x-frame-options', 'DENY');
    response.setHeader('cross-origin-resource-policy', 'same-origin');
    response.setHeader('content-security-policy', `default-src 'none'; base-uri 'none'; frame-ancestors 'none'; form-action ${new URL(this.service.configuration.alipayGateway).origin}`);
    if (result instanceof ServiceFault) {
      response.statusCode = result.status;
      if (result.retryAfter !== undefined) response.setHeader('retry-after', String(result.retryAfter));
      if (!this.request.complete) {
        this.request.pause();
        response.setHeader('connection', 'close');
      }
      response.setHeader('content-type', 'application/json; charset=utf-8');
      response.end(JSON.stringify({ error: result.error }));
    } else if (typeof result.html === 'string') {
      response.setHeader('content-type', 'text/html; charset=utf-8');
      response.end(result.html);
    } else if (typeof result.text === 'string') {
      response.setHeader('content-type', 'text/plain; charset=utf-8');
      response.end(result.text);
    } else {
      response.setHeader('content-type', 'application/json; charset=utf-8');
      response.end(JSON.stringify(result));
    }
  }
  fail(error) {
    // 语法错误是显式 HTTP 输入失败；其它异常立即抛出，由服务管理器重启，不掩盖数据库或签名错误。
    if (error instanceof SyntaxError) { this.complete(new ServiceFault(400, '请求 JSON 格式无效')); return; }
    throw error;
  }
}

class HTTPService {
  constructor(service) {
    if (!(service instanceof CommerceService)) throw new Error('必须注入 CommerceService');
    this.service = service;
    this.rateLimits = new Map();
    this.server = createServer(this.handle.bind(this));
    this.server.requestTimeout = service.configuration.requestTimeoutMilliseconds;
    this.server.headersTimeout = service.configuration.requestTimeoutMilliseconds;
    this.server.maxHeadersCount = 64;
  }
  authenticatedClientAddress(request) {
    if (!['127.0.0.1', '::1', '::ffff:127.0.0.1'].includes(request.socket.remoteAddress)) return new ServiceFault(403, '仅接受经过认证的回环反向代理');
    let addressHeaders = 0;
    let tokenHeaders = 0;
    for (let index = 0; index < request.rawHeaders.length; index += 2) {
      const name = request.rawHeaders[index].toLowerCase();
      if (name === 'x-real-ip') addressHeaders += 1;
      if (name === 'x-supercleaner-proxy-token') tokenHeaders += 1;
    }
    const token = request.headers['x-supercleaner-proxy-token'];
    const address = request.headers['x-real-ip'];
    if (addressHeaders !== 1 || tokenHeaders !== 1 || typeof address !== 'string' || isIP(address) === 0 || typeof token !== 'string' || !/^[A-Za-z0-9_-]{43}$/.test(token)) return new ServiceFault(403, '反向代理身份或客户端地址无效');
    if (!timingSafeEqual(Buffer.from(token), Buffer.from(this.service.configuration.proxySharedSecret))) return new ServiceFault(403, '反向代理身份或客户端地址无效');
    return address;
  }
  rateLimit(pathname, remoteAddress) {
    const configuration = this.service.configuration;
    const timestamp = Math.floor(performance.now() / 1000);
    // 固定窗口相同，插入顺序即到期顺序；每个过期计数桶只清理一次。
    for (const [storedKey, storedBucket] of this.rateLimits) {
      if (storedBucket.expires > timestamp) break;
      this.rateLimits.delete(storedKey);
    }
    const channel = pathname === '/v1/alipay/notify' ? 'notify' : 'client';
    const key = `${remoteAddress}:${channel}`;
    let bucket = this.rateLimits.get(key);
    if (bucket === undefined || bucket.expires <= timestamp) {
      if (this.rateLimits.size >= 65536) {
        const fault = new ServiceFault(429, '活跃客户端数量达到安全上限，请稍后重试');
        fault.retryAfter = configuration.rateLimitWindowSeconds;
        return fault;
      }
      bucket = { expires: timestamp + configuration.rateLimitWindowSeconds, requests: 0, orders: 0 };
      this.rateLimits.set(key, bucket);
    }
    if (bucket.requests >= configuration.requestRateLimitMax || (pathname === '/v1/orders' && bucket.orders >= configuration.orderRateLimitMax)) {
      const fault = new ServiceFault(429, '请求过于频繁，请稍后重试');
      fault.retryAfter = Math.max(1, bucket.expires - timestamp);
      return fault;
    }
    bucket.requests += 1;
    if (pathname === '/v1/orders') bucket.orders += 1;
    return true;
  }
  handle(request, response) { new HTTPRequest(this.service, request, response, this).start(); }
  async listen(port, host) { this.server.listen(port, host); await once(this.server, 'listening'); }
  address() { return this.server.address(); }
  async close() { this.server.close(); await once(this.server, 'close'); }
}

export function createHTTPServer(service) { return new HTTPService(service); }
