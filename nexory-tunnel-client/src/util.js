import os from 'node:os';

export function defaultSubdomain(localPort) {
  const host = os
    .hostname()
    .split('.')[0]
    .toLowerCase()
    .replace(/[^a-z0-9]+/g, '-')
    .replace(/^-+|-+$/g, '');
  return `${host || 'dev'}-${localPort}`;
}
