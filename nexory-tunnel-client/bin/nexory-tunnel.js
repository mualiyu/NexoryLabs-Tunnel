#!/usr/bin/env node

import { runLogin } from '../src/commands/login.js';
import { runHttp } from '../src/commands/http.js';
import { runTcp } from '../src/commands/tcp.js';
import { runVersion } from '../src/commands/version.js';
import { printHelp } from '../src/help.js';

const [cmd, ...args] = process.argv.slice(2);

try {
  switch (cmd) {
    case 'login':
      await runLogin();
      break;
    case 'http':
      await runHttp(args);
      break;
    case 'tcp':
      await runTcp(args);
      break;
    case 'version':
      await runVersion();
      break;
    case undefined:
    case '-h':
    case '--help':
    case 'help':
      printHelp();
      break;
    default:
      console.error(`Unknown command: ${cmd}  (try: nexory-tunnel --help)`);
      process.exit(1);
  }
} catch (err) {
  console.error(`[x] ${err.message}`);
  process.exit(1);
}
