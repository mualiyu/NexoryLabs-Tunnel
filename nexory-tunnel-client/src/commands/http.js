import { loadConfig, requireToken } from '../config.js';
import { log } from '../log.js';
import { runFrpc } from '../run.js';
import { defaultSubdomain } from '../util.js';

export async function runHttp(args) {
  const localPort = args[0];
  if (!localPort) throw new Error('Usage: nexory-tunnel http <local_port> [subdomain]');

  const config = loadConfig();
  requireToken(config);

  const sub = args[1] || defaultSubdomain(localPort);
  log(`Exposing http://127.0.0.1:${localPort}  ->  https://${sub}.${config.domain}`);

  await runFrpc(
    config,
    `[[proxies]]
name = "${sub}"
type = "http"
localIP = "127.0.0.1"
localPort = ${localPort}
subdomain = "${sub}"`,
  );
}
