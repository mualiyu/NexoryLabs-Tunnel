import readline from 'node:readline/promises';
import { stdin as input, stdout as output } from 'node:process';
import { loadConfig, saveConfig } from '../config.js';
import { DEFAULT_DOMAIN, DEFAULT_PORT, DEFAULT_SERVER } from '../defaults.js';
import { log } from '../log.js';

function ask(rl, prompt, fallback) {
  const suffix = fallback ? ` [${fallback}]` : '';
  return rl.question(`${prompt}${suffix}: `).then((v) => v.trim() || fallback || '');
}

export async function runLogin() {
  const current = loadConfig();
  const rl = readline.createInterface({ input, output });

  try {
    const serverAddr = await ask(rl, 'Server address', current.serverAddr || DEFAULT_SERVER);
    const portStr = await ask(rl, 'Server port', String(current.serverPort || DEFAULT_PORT));
    const domain = await ask(rl, 'Base domain', current.domain || DEFAULT_DOMAIN);
    const token = await ask(rl, 'Auth token', '');

    if (!token) throw new Error('Token is required.');

    const configFile = saveConfig({
      serverAddr,
      serverPort: Number(portStr),
      domain,
      token,
    });

    log(`Saved config to ${configFile}`);
  } finally {
    rl.close();
  }
}
