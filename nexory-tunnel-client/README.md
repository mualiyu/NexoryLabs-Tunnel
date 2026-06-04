# @nexorylabs/tunnel

CLI client for the [NexoryLabs Tunnel Server](https://github.com/mualiyu/NexoryLabs-Tunnel). Wraps `frpc` to expose local HTTP and TCP ports at `*.tunnel.nexorylabs.com`.

## Requirements

- Node.js 18+
- Auth token from your tunnel server Dashboard at (https://tunnel.nexorylabs.com)

## Install

From npm (recommended):

```bash
npm install -g @nexorylabs/tunnel
```

From this monorepo (development):

```bash
cd nexory-tunnel-client
npm install
npm link          # optional: global `nexory-tunnel` command
```

From git:

```bash
npm install -g "github:mualiyu/NexoryLabs-Tunnel#main:nexory-tunnel-client"
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

## Publish (maintainers)

1. Create the `@nexorylabs` org on [npmjs.com](https://www.npmjs.com/org/create) (if it does not exist).
2. `npm login` with an account that can publish to `@nexorylabs`.
3. From this directory:

```bash
npm version patch   # or minor / major
npm publish
```

Or tag a GitHub Release — CI publishes automatically (see `.github/workflows/publish-npm.yml`).
