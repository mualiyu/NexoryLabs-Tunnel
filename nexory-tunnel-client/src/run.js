import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { spawn } from 'node:child_process';
import { ensureFrpc } from './frpc.js';

export async function runFrpc(config, proxyBlock) {
  const conf = [
    `serverAddr = "${config.serverAddr}"`,
    `serverPort = ${config.serverPort}`,
    `auth.token = "${config.token}"`,
    '',
    proxyBlock,
  ].join('\n');

  const confPath = path.join(os.tmpdir(), `frpc-${process.pid}-${Date.now()}.toml`);
  fs.writeFileSync(confPath, conf, { mode: 0o600 });

  const frpc = await ensureFrpc();
  const child = spawn(frpc, ['-c', confPath], { stdio: 'inherit' });

  const cleanup = () => {
    try {
      fs.unlinkSync(confPath);
    } catch {
      /* ignore */
    }
  };

  child.on('exit', cleanup);
  child.on('error', (err) => {
    cleanup();
    throw err;
  });

  process.on('SIGINT', () => child.kill('SIGINT'));
  process.on('SIGTERM', () => child.kill('SIGTERM'));

  await new Promise((resolve, reject) => {
    child.on('exit', (code, signal) => {
      if (signal) resolve();
      else if (code === 0) resolve();
      else reject(new Error(`frpc exited with code ${code}`));
    });
    child.on('error', reject);
  });
}
