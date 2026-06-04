import { spawnSync } from 'node:child_process';
import { ensureFrpc } from '../frpc.js';

export async function runVersion() {
  const frpc = await ensureFrpc();
  const result = spawnSync(frpc, ['--version'], { encoding: 'utf8' });
  if (result.stdout) process.stdout.write(result.stdout);
  if (result.stderr) process.stderr.write(result.stderr);
  if (result.status !== 0) process.exit(result.status ?? 1);
}
