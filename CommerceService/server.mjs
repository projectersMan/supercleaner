import { CommerceService, loadConfiguration } from './commerce.mjs';
import { createHTTPServer } from './http.mjs';

function validateRuntime() {
  const version = process.versions.node.split('.');
  if (Number(version[0]) < 24 || (Number(version[0]) === 24 && Number(version[1]) < 13)) throw new Error('CommerceService 需要 Node.js 24.13 或更高版本');
}

class ServerLifecycle {
  constructor(service, server) { this.service = service; this.server = server; this.stopping = false; }
  async stop() {
    if (this.stopping) return;
    this.stopping = true;
    await this.server.close();
    this.service.close();
  }
}

validateRuntime();
if (process.argv.length !== 3) throw new Error('用法：node CommerceService/server.mjs /绝对路径/config.json');
process.umask(0o077);
const configuration = loadConfiguration(process.argv[2]);
const service = new CommerceService(configuration);
const server = createHTTPServer(service);
const lifecycle = new ServerLifecycle(service, server);
process.on('SIGTERM', lifecycle.stop.bind(lifecycle));
process.on('SIGINT', lifecycle.stop.bind(lifecycle));
await server.listen(configuration.port, configuration.host);
console.log(`SuperCleaner CommerceService 已监听 ${configuration.host}:${configuration.port}；公网 HTTPS 必须由反向代理提供。`);
