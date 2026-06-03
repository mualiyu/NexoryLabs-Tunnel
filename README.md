# Nexory Tunnel

Your own self-hosted, ngrok-style tunnel built on [frp](https://github.com/fatedier/frp).
Expose local web apps and TCP ports to the internet under
`*.tunnel.nexorylabs.com` with automatic HTTPS — **everything runs on the
server and it needs no DNS provider access.**

```
Browser ──HTTPS──► Caddy (:443, per-subdomain TLS issued on demand via HTTP-01)
                     │  reverse_proxy (Host header preserved)
                     ├─ *.tunnel.nexorylabs.com ─► frps HTTP vhost (:8080)
                     └─ tunnel.nexorylabs.com   ─► frps dashboard (:7500)
                   frps (:7000 client bind · :20000-30000 raw TCP)
                     └── frpc (your laptop) ──► your local service (e.g. :3000)
```

- **Server**: `frps` + `Caddy` on your AWS box `3.12.247.90`.
- **Client**: `frpc`, driven by the `nexory-tunnel` CLI, on your laptop.
- **TLS**: Caddy issues a real Let's Encrypt cert for each subdomain the
  first time it's requested, using the **HTTP-01 challenge** (port 80). No DNS
  API, no Route 53 access, no wildcard cert needed. A localhost-only authorizer
  restricts issuance to `*.tunnel.nexorylabs.com` so the feature can't be abused.

---

## Prerequisites (already done ✅)

DNS is in place — verified live:

| Record | Type | Value |
| --- | --- | --- |
| `tunnel.nexorylabs.com` | A | `3.12.247.90` |
| `*.tunnel.nexorylabs.com` | A | `3.12.247.90` |

That's all the DNS you need — no API access or credentials. Because `*` resolves
to the server, Caddy can complete the HTTP-01 challenge for any subdomain itself.

### Open the ports in your AWS Security Group

`ufw` is configured by the script, but on EC2 the **Security Group** is the real gate.
Add inbound rules for:

| Port(s) | Protocol | Purpose |
| --- | --- | --- |
| 22 | TCP | SSH |
| 80 | TCP | Caddy (HTTP → HTTPS redirect + ACME HTTP-01 challenge) |
| 443 | TCP | Caddy (HTTPS) |
| 7000 | TCP | frpc client connections |
| 20000–30000 | TCP | raw TCP tunnels |

> Port 80 **must** be reachable from the internet — that's how the certificates
> are validated. The on-demand authorizer (`:9123`) stays bound to localhost.

---

## Server setup

Copy `setup-server.sh` to the server and run it as root:

```bash
scp setup-server.sh ubuntu@3.12.247.90:~
ssh ubuntu@3.12.247.90
sudo ./setup-server.sh
```

The script installs `frps` + `Caddy`, writes systemd units, configures `ufw`, and
prints (and saves to `/etc/frp/tunnel-credentials.txt`) your **auth token** and
**dashboard password**. Keep the token — clients need it.

Certificates are issued lazily — the first time you visit a given subdomain.
Watch it happen:

```bash
sudo journalctl -u caddy -f      # look for "certificate obtained successfully"
sudo systemctl status frps caddy
```

> **Let's Encrypt rate limits:** ~50 certs per registered domain per week, so
> avoid spinning up endless one-off random subdomains. `nexory-tunnel http` defaults
> to a **stable** name (`<hostname>-<port>`) for exactly this reason — reuse
> names and certs get reused/renewed instead of re-issued.

### Useful server config knobs (env vars)

| Variable | Default | Meaning |
| --- | --- | --- |
| `DOMAIN` | `tunnel.nexorylabs.com` | base tunnel domain |
| `ACME_EMAIL` | `admin@nexorylabs.com` | Let's Encrypt contact |
| `FRP_VERSION` | latest | pin an frp version |
| `TCP_PORT_START` / `TCP_PORT_END` | `20000` / `30000` | allowed raw-TCP range |
| `FRP_TOKEN` | auto-generated | client auth token |
| `DASHBOARD_PASS` | auto-generated | dashboard password |

---

## Client usage (your laptop)

### Option A — install the `.deb` package (recommended on Ubuntu/Debian)

Build the package on a Linux machine (needs `debhelper`, `curl`):

```bash
sudo apt install build-essential devscripts debhelper curl
git clone https://github.com/mualiyu/NexoryLabs-Tunnel.git && cd NexoryLabs-Tunnel
make deb
sudo apt install ../nexory-tunnel_1.0.2_amd64.deb
```

On **arm64** (e.g. Raspberry Pi, Graviton), build with `make deb-arm64` instead.

This installs:

| Path | Purpose |
| --- | --- |
| `/usr/bin/nexory-tunnel` | main CLI |
| `/usr/bin/tunnel` | symlink to `nexory-tunnel` |
| `/usr/lib/nexory-tunnel/frpc` | bundled frpc (v0.69.1) |
| `/etc/nexory-tunnel/default` | server defaults (no token) |

Or download a pre-built `.deb` from [GitHub Releases](https://github.com/mualiyu/NexoryLabs-Tunnel/releases) and install:

```bash
sudo apt install ./nexory-tunnel_1.0.2_amd64.deb
```

### Option B — run the script directly

```bash
chmod +x tunnel.sh
./tunnel.sh login
./tunnel.sh http 3000
```

(`frpc` is downloaded on first run into `~/.config/nexory-tunnel/bin`.)

### Commands

One-time login (paste the token from the server output):

```bash
nexory-tunnel login
```

Expose a local web app — gets HTTPS automatically:

```bash
nexory-tunnel http 3000              # → https://<hostname>-3000.tunnel.nexorylabs.com
nexory-tunnel http 3000 myapp        # → https://myapp.tunnel.nexorylabs.com
```

Expose a raw TCP port (SSH, Postgres, game server, …):

```bash
nexory-tunnel tcp 22 25022           # → tunnel.nexorylabs.com:25022
nexory-tunnel tcp 5432               # → auto-assigned port (shown in output/dashboard)
```

Press `Ctrl+C` to close a tunnel. User config (token) lives in
`~/.config/nexory-tunnel/config`; system defaults in `/etc/nexory-tunnel/default`.

The dashboard (live tunnels, traffic stats) is at `https://tunnel.nexorylabs.com`.

---

## How it fits together

- `frps` does subdomain routing via `subDomainHost`, so a client with
  `subdomain = "myapp"` is reachable at `myapp.tunnel.nexorylabs.com`.
- Caddy preserves the incoming `Host` header when proxying, so frps can route
  correctly while Caddy handles all public TLS.
- Caddy's **on-demand TLS** asks a localhost endpoint (`:9123`) before issuing a
  cert; it only says "yes" for names ending in `.tunnel.nexorylabs.com`, then
  completes an HTTP-01 challenge on port 80. No DNS provider is ever contacted.
- The frpc↔frps control connection (port 7000) is TLS-encrypted by default
  (frp ≥ v0.50) and authenticated with the shared token.

## Troubleshooting

| Symptom | Check |
| --- | --- |
| Cert never issues | `journalctl -u caddy -f`; ensure port **80** is open to the internet in the Security Group (HTTP-01 needs it), and that the subdomain resolves to the server |
| `connection refused` from client | Security Group missing port 7000; `systemctl status frps` |
| Subdomain 404 / "not found" | client `subdomain` not set, or frpc not connected — check the dashboard |
| TCP tunnel unreachable | remote port outside `20000–30000`, or Security Group missing the range |

## Managing services

```bash
sudo systemctl restart frps
sudo systemctl restart caddy
sudo journalctl -u frps -e
sudo journalctl -u caddy -e
```

## Files

| File | Runs on | Purpose |
| --- | --- | --- |
| `setup-server.sh` | AWS server | install + configure frps & Caddy |
| `tunnel.sh` | your laptop | CLI source (installed as `/usr/bin/nexory-tunnel`) |
| `debian/` | build host | Debian package metadata |
| `etc/nexory-tunnel/default` | client (via package) | system-wide server defaults |
