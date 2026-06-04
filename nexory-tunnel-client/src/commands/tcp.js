import { loadConfig, requireToken } from '../config.js';
import { log } from '../log.js';
import { runFrpc } from '../run.js';

export async function runTcp(args) {
  const localPort = args[0];
  if (!localPort) throw new Error('Usage: nexory-tunnel tcp <local_port> [remote_port]');

  const config = loadConfig();
  requireToken(config);

  const remotePort = args[1];
  const name = `tcp-${localPort}-${Date.now()}`;
  const remoteLine = remotePort
    ? `remotePort = ${remotePort}`
    : 'remotePort = 0';

  if (remotePort) {
    log(`Exposing tcp 127.0.0.1:${localPort}  ->  ${config.domain}:${remotePort}`);
  } else {
    log(`Exposing tcp 127.0.0.1:${localPort}  ->  ${config.domain}:<auto-assigned>`);
  }

  await runFrpc(
    config,
    `[[proxies]]
name = "${name}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${localPort}
${remoteLine}`,
  );
}
