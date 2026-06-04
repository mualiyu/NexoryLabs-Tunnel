# NexoryLabs Tunnel Server

Monorepo for the NexoryLabs self-hosted tunnel:

| Directory | Purpose |
| --- | --- |
| `/` (root) | **Server** — `setup-server.sh`, frps + Caddy on AWS |
| [`nexory-tunnel-client/`](./nexory-tunnel-client) | **Client** — npm CLI (`nexory-tunnel`) |

Self-hosted tunnel **server** — exposes frp (`frps`) + Caddy on your AWS box so clients can share local ports at `*.tunnel.nexorylabs.com` with automatic HTTPS.

> **Client:** [`nexory-tunnel-client/`](./nexory-tunnel-client) — npm CLI (`nexory-tunnel login`, `http`, `tcp`)

```
Browser ──HTTPS──► Caddy (:443, per-subdomain TLS via HTTP-01)
                     ├─ *.tunnel.nexorylabs.com ─► frps HTTP vhost (:8080)
                     └─ tunnel.nexorylabs.com   ─► frps dashboard (:7500)
                   frps (:7000 · TCP 20000–30000)
                     └── frpc (client) ──► local service (e.g. :3000)
```

- **Server** (this repo): `frps` + Caddy on `3.12.247.90`
- **TLS**: on-demand Let's Encrypt per subdomain — no DNS API access required
- **Auth**: shared token between `frps` and all `frpc` clients

---

## Prerequisites

### DNS

| Record | Type | Value |
| --- | --- | --- |
| `tunnel.nexorylabs.com` | A | your server IP |
| `*.tunnel.nexorylabs.com` | A | your server IP |

### AWS Security Group (inbound)

| Port(s) | Protocol | Purpose |
| --- | --- | --- |
| 22 | TCP | SSH |
| 80 | TCP | Caddy (HTTP-01 ACME challenge) |
| 443 | TCP | Caddy (HTTPS) |
| 7000 | TCP | frpc client connections |
| 20000–30000 | TCP | raw TCP tunnels |

Port **80** must be public. Stop or disable **nginx** on the box if it already owns `:80`/`:443` — Caddy needs those ports.

---

## Install

```bash
git clone https://github.com/mualiyu/NexoryLabs-Tunnel.git
cd NexoryLabs-Tunnel
cp .env.example .env    # set FRP_TOKEN, DASHBOARD_PASS, ACME_EMAIL
sudo ./setup-server.sh
```

Or copy only the script:

```bash
scp setup-server.sh .env ubuntu@3.12.247.90:~
ssh ubuntu@3.12.247.90
sudo ./setup-server.sh
```

The script installs `frps` + Caddy, configures `ufw`, enables systemd services, and saves credentials to `/etc/frp/tunnel-credentials.txt`. **Give the auth token to anyone who needs to connect a client.**

After install:

```bash
sudo systemctl status frps caddy
sudo journalctl -u caddy -f    # watch TLS cert issuance
```

Dashboard: `https://tunnel.nexorylabs.com`

---

## Configuration

Create `.env` next to `setup-server.sh` (loaded automatically):

| Variable | Default | Meaning |
| --- | --- | --- |
| `FRP_TOKEN` | auto-generated | client auth token |
| `DASHBOARD_USER` | `admin` | dashboard username |
| `DASHBOARD_PASS` | auto-generated | dashboard password |
| `ACME_EMAIL` | `admin@nexorylabs.com` | Let's Encrypt contact |
| `DOMAIN` | `tunnel.nexorylabs.com` | base tunnel domain |
| `FRP_VERSION` | latest | pin frp version |
| `TCP_PORT_START` / `TCP_PORT_END` | `20000` / `30000` | allowed raw-TCP range |

Re-run `setup-server.sh` after editing `.env`, then:

```bash
sudo systemctl restart frps caddy
```

---

## Client (npm)

Install and use the CLI from [`nexory-tunnel-client/`](./nexory-tunnel-client):

```bash
cd nexory-tunnel-client
npm install
npm link
nexory-tunnel login
nexory-tunnel http 3000 myapp    # → https://myapp.tunnel.nexorylabs.com
```

See [nexory-tunnel-client/README.md](./nexory-tunnel-client/README.md) for full usage.

---

## Client connection (frpc config reference)

Clients need:

```
serverAddr = "tunnel.nexorylabs.com"
serverPort = 7000
auth.token = "<FRP_TOKEN from server>"
```

Example frpc proxy for a local web app on port 3000:

```toml
[[proxies]]
name = "myapp"
type = "http"
localPort = 3000
subdomain = "myapp"
```

→ `https://myapp.tunnel.nexorylabs.com`

---

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Caddy fails: `address already in use` | nginx/apache on `:80`/`:443` — disable them |
| Cert never issues | Security Group allows port 80; subdomain resolves to server |
| Client `connection refused` | Security Group allows port 7000; `systemctl status frps` |
| Subdomain 404 | frpc not connected or wrong `subdomain` — check dashboard |
| TCP tunnel unreachable | remote port outside `20000–30000` or SG missing range |

```bash
sudo systemctl restart frps caddy
sudo journalctl -u frps -e
sudo journalctl -u caddy -e
```

---

## Repository layout

| Path | Purpose |
| --- | --- |
| `setup-server.sh` | server installer |
| `.env.example` | server credential template |
| `nexory-tunnel-client/` | npm CLI client |
| `README.md` | server documentation |

---

## Related

- [frp](https://github.com/fatedier/frp) — reverse proxy engine
- [nexory-tunnel-client](./nexory-tunnel-client) — Node.js client CLI
