import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { DEFAULT_DOMAIN, DEFAULT_PORT, DEFAULT_SERVER } from './defaults.js';

const CONFIG_DIR = path.join(
  process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
  'nexory-tunnel',
);
const CONFIG_FILE = path.join(CONFIG_DIR, 'config');

function parseConfigFile(content) {
  const out = {};
  for (const line of content.split('\n')) {
    const m = line.match(/^([A-Z_]+)="(.*)"\s*$/);
    if (m) out[m[1]] = m[2];
  }
  return out;
}

function serializeConfig(cfg) {
  return [
    `SERVER_ADDR="${cfg.SERVER_ADDR}"`,
    `SERVER_PORT="${cfg.SERVER_PORT}"`,
    `DOMAIN="${cfg.DOMAIN}"`,
    `TOKEN="${cfg.TOKEN}"`,
    '',
  ].join('\n');
}

export function loadConfig() {
  const cfg = {
    SERVER_ADDR: DEFAULT_SERVER,
    SERVER_PORT: String(DEFAULT_PORT),
    DOMAIN: DEFAULT_DOMAIN,
    TOKEN: '',
  };

  if (fs.existsSync(CONFIG_FILE)) {
    Object.assign(cfg, parseConfigFile(fs.readFileSync(CONFIG_FILE, 'utf8')));
  }

  return {
    serverAddr: cfg.SERVER_ADDR || DEFAULT_SERVER,
    serverPort: Number(cfg.SERVER_PORT || DEFAULT_PORT),
    domain: cfg.DOMAIN || DEFAULT_DOMAIN,
    token: cfg.TOKEN || '',
    configFile: CONFIG_FILE,
  };
}

export function saveConfig({ serverAddr, serverPort, domain, token }) {
  fs.mkdirSync(CONFIG_DIR, { recursive: true, mode: 0o700 });
  fs.writeFileSync(
    CONFIG_FILE,
    serializeConfig({
      SERVER_ADDR: serverAddr,
      SERVER_PORT: String(serverPort),
      DOMAIN: domain,
      TOKEN: token,
    }),
    { mode: 0o600 },
  );
  return CONFIG_FILE;
}

export function requireToken(config) {
  if (!config.token) {
    throw new Error('No auth token configured. Run:  nexory-tunnel login');
  }
}
