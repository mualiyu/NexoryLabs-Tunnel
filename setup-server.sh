#!/usr/bin/env bash
#
# setup-server.sh — Set up a self-hosted ngrok-style tunnel server using frp + Caddy.
#
# Run this ON your Ubuntu AWS server (3.12.247.90). It will:
#   1. Install frps (frp server) from the official GitHub release.
#   2. Configure subdomain-based HTTP routing + a range of raw TCP ports.
#   3. Install Caddy as a TLS terminator that issues a certificate per
#      subdomain ON DEMAND via the HTTP-01 challenge (no DNS API needed).
#   4. Create systemd services for both, and open the firewall (ufw).
#
# Everything runs on this server. It needs NO DNS provider access — it only
# relies on the existing A records:
#   tunnel.nexorylabs.com    -> this server
#   *.tunnel.nexorylabs.com  -> this server
# Because every subdomain resolves here, Caddy can prove ownership over HTTP
# (port 80) and obtain a real Let's Encrypt cert the first time each
# subdomain is requested.
#
# Usage:
#   cp .env.example .env   # edit with your credentials
#   sudo ./setup-server.sh
#
# Optional environment overrides (sensible defaults below).
# Values in .env (same directory as this script) are loaded automatically.
#
#   DOMAIN=tunnel.nexorylabs.com
#   ACME_EMAIL=you@example.com
#   FRP_VERSION=0.69.1            # pin a version; empty = latest
#   TCP_PORT_START=20000
#   TCP_PORT_END=30000
#   FRP_TOKEN=...                 # auth token; auto-generated if unset
#   DASHBOARD_USER=admin
#   DASHBOARD_PASS=...            # auto-generated if unset
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ENV_FILE="${ENV_FILE:-$SCRIPT_DIR/.env}"
if [ -f "$ENV_FILE" ]; then
  set -a
  # shellcheck disable=SC1090,SC1091
  . "$ENV_FILE"
  set +a
fi

# ----------------------------------------------------------------------------
# Configuration
# ----------------------------------------------------------------------------
DOMAIN="${DOMAIN:-tunnel.nexorylabs.com}"
ACME_EMAIL="${ACME_EMAIL:-admin@nexorylabs.com}"
FRP_VERSION="${FRP_VERSION:-}"          # empty = resolve latest from GitHub
TCP_PORT_START="${TCP_PORT_START:-20000}"
TCP_PORT_END="${TCP_PORT_END:-30000}"

FRP_BIND_PORT=7000                       # frpc clients connect here
FRP_VHOST_HTTP_PORT=8080                 # internal; Caddy proxies to this
FRP_DASHBOARD_PORT=7500                  # internal; Caddy proxies to this
ASK_PORT=9123                            # internal; Caddy on-demand TLS authorizer

FRP_TOKEN="${FRP_TOKEN:-}"
DASHBOARD_USER="${DASHBOARD_USER:-admin}"
DASHBOARD_PASS="${DASHBOARD_PASS:-}"

INSTALL_DIR="/usr/local/bin"
FRP_CONF_DIR="/etc/frp"
FRP_LOG_DIR="/var/log/frp"
CADDY_CONF_DIR="/etc/caddy"

# ----------------------------------------------------------------------------
# Helpers
# ----------------------------------------------------------------------------
log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

[ "$(id -u)" -eq 0 ] || die "Please run as root:  sudo ./setup-server.sh"

gen_secret() { head -c 32 /dev/urandom | base64 | tr -dc 'A-Za-z0-9' | head -c 32; }

FRP_TOKEN="${FRP_TOKEN:-$(gen_secret)}"
DASHBOARD_PASS="${DASHBOARD_PASS:-$(gen_secret)}"

detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    armv7l) echo "arm" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}
ARCH="$(detect_arch)"

# ----------------------------------------------------------------------------
# 1. System packages
# ----------------------------------------------------------------------------
log "Installing prerequisites (curl, tar, ufw)..."
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq curl tar ufw ca-certificates >/dev/null

# ----------------------------------------------------------------------------
# 2. Install frps
# ----------------------------------------------------------------------------
if [ -z "$FRP_VERSION" ]; then
  log "Resolving latest frp release..."
  FRP_VERSION="$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest \
    | grep -oP '"tag_name":\s*"v\K[^"]+' || true)"
  [ -n "$FRP_VERSION" ] || die "Could not resolve latest frp version. Set FRP_VERSION manually."
fi
log "Using frp v${FRP_VERSION} (${ARCH})"

TARBALL="frp_${FRP_VERSION}_linux_${ARCH}.tar.gz"
URL="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${TARBALL}"
TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT

log "Downloading ${URL}"
curl -fsSL "$URL" -o "$TMP/$TARBALL" || die "Download failed: $URL"
tar -xzf "$TMP/$TARBALL" -C "$TMP"
FRP_SRC="$TMP/frp_${FRP_VERSION}_linux_${ARCH}"

install -m 0755 "$FRP_SRC/frps" "$INSTALL_DIR/frps"
log "Installed frps -> $INSTALL_DIR/frps"

# ----------------------------------------------------------------------------
# 3. frps configuration
# ----------------------------------------------------------------------------
mkdir -p "$FRP_CONF_DIR" "$FRP_LOG_DIR"

cat > "$FRP_CONF_DIR/frps.toml" <<EOF
# Managed by setup-server.sh — frp server (frps) configuration.

bindPort = ${FRP_BIND_PORT}

# HTTP vhost: Caddy terminates TLS and reverse-proxies here.
vhostHTTPPort = ${FRP_VHOST_HTTP_PORT}

# Every client subdomain becomes <name>.${DOMAIN}
subDomainHost = "${DOMAIN}"

# Raw TCP tunnels are restricted to this port range.
allowPorts = [
  { start = ${TCP_PORT_START}, end = ${TCP_PORT_END} },
]

# Client authentication.
auth.method = "token"
auth.token = "${FRP_TOKEN}"

# Dashboard (kept on localhost; exposed via Caddy at https://${DOMAIN}).
webServer.addr = "127.0.0.1"
webServer.port = ${FRP_DASHBOARD_PORT}
webServer.user = "${DASHBOARD_USER}"
webServer.password = "${DASHBOARD_PASS}"

log.to = "${FRP_LOG_DIR}/frps.log"
log.level = "info"
log.maxDays = 7
EOF
chmod 600 "$FRP_CONF_DIR/frps.toml"
log "Wrote $FRP_CONF_DIR/frps.toml"

cat > /etc/systemd/system/frps.service <<EOF
[Unit]
Description=frp server (frps)
After=network.target

[Service]
Type=simple
ExecStart=${INSTALL_DIR}/frps -c ${FRP_CONF_DIR}/frps.toml
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------------------------------
# 4. Install Caddy (standard build) for on-demand HTTP-01 TLS
# ----------------------------------------------------------------------------
log "Downloading Caddy..."
CADDY_URL="https://caddyserver.com/api/download?os=linux&arch=${ARCH}"
curl -fsSL "$CADDY_URL" -o "$TMP/caddy" || die "Caddy download failed"
install -m 0755 "$TMP/caddy" "$INSTALL_DIR/caddy"
log "Installed caddy -> $INSTALL_DIR/caddy"

# Dedicated system user for Caddy.
if ! id caddy >/dev/null 2>&1; then
  useradd --system --home /var/lib/caddy --shell /usr/sbin/nologin --create-home caddy
fi
mkdir -p "$CADDY_CONF_DIR" /var/lib/caddy
chown -R caddy:caddy /var/lib/caddy

cat > "$CADDY_CONF_DIR/Caddyfile" <<EOF
# Managed by setup-server.sh — Caddy reverse proxy + on-demand HTTPS.
{
	email ${ACME_EMAIL}
	# Only allow on-demand certs for our tunnel subdomains (prevents abuse).
	on_demand_tls {
		ask http://127.0.0.1:${ASK_PORT}
	}
}

# Internal authorizer for on-demand TLS. Bound to localhost only.
# Caddy calls it as ...?domain=<hostname>; 200 = allowed, anything else = denied.
http://127.0.0.1:${ASK_PORT} {
	@ok expression \`{query.domain}.endsWith(".${DOMAIN}")\`
	respond @ok 200
	respond 403
}

# Dashboard at the apex tunnel domain (normal HTTP-01 cert).
${DOMAIN} {
	reverse_proxy 127.0.0.1:${FRP_DASHBOARD_PORT}
}

# Every tunnel subdomain. Certs are issued on first request (HTTP-01),
# then traffic is proxied to frps with the Host header preserved.
https:// {
	tls {
		on_demand
	}
	@tunnel host *.${DOMAIN}
	handle @tunnel {
		reverse_proxy 127.0.0.1:${FRP_VHOST_HTTP_PORT}
	}
	handle {
		respond "Unknown tunnel host" 404
	}
}
EOF
log "Wrote $CADDY_CONF_DIR/Caddyfile"

cat > /etc/systemd/system/caddy.service <<EOF
[Unit]
Description=Caddy (frp tunnel TLS terminator)
After=network.target network-online.target
Requires=network-online.target

[Service]
Type=notify
User=caddy
Group=caddy
ExecStart=${INSTALL_DIR}/caddy run --environ --config ${CADDY_CONF_DIR}/Caddyfile
ExecReload=${INSTALL_DIR}/caddy reload --config ${CADDY_CONF_DIR}/Caddyfile --force
TimeoutStopSec=5s
LimitNOFILE=1048576
PrivateTmp=true
ProtectSystem=full
AmbientCapabilities=CAP_NET_BIND_SERVICE

[Install]
WantedBy=multi-user.target
EOF

# ----------------------------------------------------------------------------
# 5. Firewall (ufw). NOTE: AWS Security Groups must also allow these ports!
# ----------------------------------------------------------------------------
log "Configuring ufw firewall..."
ufw allow 22/tcp           >/dev/null   # SSH (don't lock yourself out)
ufw allow 80/tcp           >/dev/null   # Caddy HTTP (redirect -> HTTPS)
ufw allow 443/tcp          >/dev/null   # Caddy HTTPS
ufw allow "${FRP_BIND_PORT}/tcp" >/dev/null   # frpc client connections
ufw allow "${TCP_PORT_START}:${TCP_PORT_END}/tcp" >/dev/null   # raw TCP tunnels
if ! ufw status | grep -q "Status: active"; then
  warn "Enabling ufw (SSH on 22 is already allowed)."
  ufw --force enable >/dev/null
fi

# ----------------------------------------------------------------------------
# 6. Start services
# ----------------------------------------------------------------------------
log "Starting services..."
systemctl daemon-reload
systemctl enable --now frps.service
systemctl enable --now caddy.service

sleep 2
systemctl is-active --quiet frps.service  || warn "frps did not start — check: journalctl -u frps -e"
systemctl is-active --quiet caddy.service || warn "caddy did not start — check: journalctl -u caddy -e"

# ----------------------------------------------------------------------------
# 7. Save & print connection details
# ----------------------------------------------------------------------------
CRED_FILE="$FRP_CONF_DIR/tunnel-credentials.txt"
cat > "$CRED_FILE" <<EOF
Nexory Tunnel — server credentials
===================================
Server domain   : ${DOMAIN}
frpc serverAddr : ${DOMAIN}   (or the public IP 3.12.247.90)
frpc serverPort : ${FRP_BIND_PORT}
Auth token      : ${FRP_TOKEN}
TCP port range  : ${TCP_PORT_START}-${TCP_PORT_END}
Dashboard       : https://${DOMAIN}   (user: ${DASHBOARD_USER}  pass: ${DASHBOARD_PASS})
EOF
chmod 600 "$CRED_FILE"

cat <<EOF

=====================================================================
 ✅  Nexory Tunnel server is set up.
=====================================================================
 Connect a client (frpc) with these values:

   serverAddr = "${DOMAIN}"
   serverPort = ${FRP_BIND_PORT}
   auth.token = "${FRP_TOKEN}"

 Dashboard : https://${DOMAIN}
   user: ${DASHBOARD_USER}   pass: ${DASHBOARD_PASS}

 Web tunnels  : https://<name>.${DOMAIN}   (frpc type=http, subdomain=<name>)
 TCP  tunnels : ${DOMAIN}:<${TCP_PORT_START}-${TCP_PORT_END}>

 Saved to ${CRED_FILE}

 ⚠️  Open these ports in your AWS Security Group too:
     22, 80, 443, ${FRP_BIND_PORT} (TCP), and ${TCP_PORT_START}-${TCP_PORT_END} (TCP)

 ℹ️  TLS is fully automatic and self-contained — no DNS access needed.
     Each subdomain's certificate is issued the first time it's visited
     (HTTP-01 over port 80), so the first request can take a few seconds.
     Watch cert issuance:  journalctl -u caddy -f
=====================================================================
EOF
