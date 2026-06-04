# Nexory Tunnel Client

Node.js CLI for connecting to a [NexoryLabs Tunnel Server](https://github.com/mualiyu/NexoryLabs-Tunnel). Wraps `frpc` to expose local HTTP and TCP ports at `*.tunnel.nexorylabs.com`.

## Requirements

- Node.js 18+
- Auth token from your tunnel server (`/etc/frp/tunnel-credentials.txt`)

## Install

From this monorepo:

```bash
cd nexory-tunnel-client
npm install
npm link          # optional: global `nexory-tunnel` command
```

Or install from git (once published):

```bash
npm install -g git+https://github.com/mualiyu/NexoryLabs-Tunnel.git#nexory-tunnel-client
```

Local development without linking:

```bash
node bin/nexory-tunnel.js login
node bin/nexory-tunnel.js http 3000
```

## Usage

```bash
nexory-tunnel login
nexory-tunnel http 3000              # https://<hostname>-3000.tunnel.nexorylabs.com
nexory-tunnel http 3000 myapp        # https://myapp.tunnel.nexorylabs.com
nexory-tunnel tcp 22 25022
nexory-tunnel version
```

Config is stored in `~/.config/nexory-tunnel/config`. `frpc` is downloaded on first use to `~/.config/nexory-tunnel/bin/` (frp v0.69.1 by default; override with `FRP_VERSION`).

Press `Ctrl+C` to stop a tunnel.

## Environment

| Variable | Default | Meaning |
| --- | --- | --- |
| `FRP_VERSION` | `0.69.1` | frp release to download |
| `XDG_CONFIG_HOME` | `~/.config` | config base directory |
