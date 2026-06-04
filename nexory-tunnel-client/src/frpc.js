import fs from 'node:fs';
import os from 'node:os';
import path from 'node:path';
import { pipeline } from 'node:stream/promises';
import { createGunzip } from 'node:zlib';
import { Readable } from 'node:stream';
import { x as extractTar } from 'tar';
import { DEFAULT_FRP_VERSION } from './defaults.js';
import { log } from './log.js';

const CACHE_DIR = path.join(
  process.env.XDG_CONFIG_HOME || path.join(os.homedir(), '.config'),
  'nexory-tunnel',
  'bin',
);
const FRPC_NAME = process.platform === 'win32' ? 'frpc.exe' : 'frpc';
const CACHE_FRPC = path.join(CACHE_DIR, FRPC_NAME);

function platformArch() {
  const osMap = { darwin: 'darwin', linux: 'linux', win32: 'windows' };
  const osName = osMap[process.platform];
  if (!osName) throw new Error(`Unsupported OS: ${process.platform}`);

  const archMap = { x64: 'amd64', arm64: 'arm64' };
  const arch = archMap[process.arch];
  if (!arch) throw new Error(`Unsupported architecture: ${process.arch}`);

  return { osName, arch };
}

export async function ensureFrpc() {
  if (fs.existsSync(CACHE_FRPC)) return CACHE_FRPC;

  const { osName, arch } = platformArch();
  const version = process.env.FRP_VERSION || DEFAULT_FRP_VERSION;
  const folder = `frp_${version}_${osName}_${arch}`;
  const tarball = `${folder}.tar.gz`;
  const url = `https://github.com/fatedier/frp/releases/download/v${version}/${tarball}`;

  log(`Downloading frpc v${version} (${osName}/${arch})...`);

  const res = await fetch(url);
  if (!res.ok) throw new Error(`Download failed: ${url}`);

  fs.mkdirSync(CACHE_DIR, { recursive: true });
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'frpc-'));

  try {
    await pipeline(
      Readable.fromWeb(res.body),
      createGunzip(),
      extractTar({ cwd: tmpDir }),
    );
    const extracted = path.join(tmpDir, folder, FRPC_NAME);
    if (!fs.existsSync(extracted)) throw new Error('frpc binary not found in archive');
    fs.copyFileSync(extracted, CACHE_FRPC);
    fs.chmodSync(CACHE_FRPC, 0o755);
  } finally {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  }

  log(`Installed frpc -> ${CACHE_FRPC}`);
  return CACHE_FRPC;
}
