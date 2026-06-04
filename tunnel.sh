#!/usr/bin/env bash
#
# nexory-tunnel — expose a local port through your Nexory tunnel server.
#
# Run on your LOCAL machine (macOS or Linux). When installed via the .deb package,
# frpc is bundled at /usr/lib/nexory-tunnel/frpc; otherwise it is downloaded on
# first use into ~/.config/nexory-tunnel/bin.
#
# First-time setup (stores server address + token in ~/.config/nexory-tunnel):
#   nexory-tunnel login
#
# Expose a local web app (http):
#   nexory-tunnel http 3000              # -> https://<hostname>-3000.tunnel.nexorylabs.com
#   nexory-tunnel http 3000 myapp        # -> https://myapp.tunnel.nexorylabs.com
#
# Expose a raw TCP port (e.g. SSH, Postgres):
#   nexory-tunnel tcp 22                 # -> tunnel.nexorylabs.com:<auto-assigned>
#   nexory-tunnel tcp 5432 25432         # -> tunnel.nexorylabs.com:25432
#
# Other:
#   nexory-tunnel version
#
set -euo pipefail

# ----------------------------------------------------------------------------
# Paths
# ----------------------------------------------------------------------------
SYSTEM_DEFAULT="/etc/nexory-tunnel/default"
SYSTEM_FRPC="/usr/lib/nexory-tunnel/frpc"

DEFAULT_SERVER="tunnel.nexorylabs.com"
DEFAULT_PORT="7000"
DEFAULT_DOMAIN="tunnel.nexorylabs.com"

CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/nexory-tunnel"
CONFIG_FILE="$CONFIG_DIR/config"
CACHE_DIR="$CONFIG_DIR/bin"
CACHE_FRPC="$CACHE_DIR/frpc"

log()  { printf '\033[1;32m[+]\033[0m %s\n' "$*"; }
warn() { printf '\033[1;33m[!]\033[0m %s\n' "$*"; }
err()  { printf '\033[1;31m[x]\033[0m %s\n' "$*" >&2; }
die()  { err "$*"; exit 1; }

# ----------------------------------------------------------------------------
# Platform detection + frpc install
# ----------------------------------------------------------------------------
detect_os() {
  case "$(uname -s)" in
    Darwin) echo "darwin" ;;
    Linux)  echo "linux" ;;
    *) die "Unsupported OS: $(uname -s)" ;;
  esac
}
detect_arch() {
  case "$(uname -m)" in
    x86_64|amd64) echo "amd64" ;;
    aarch64|arm64) echo "arm64" ;;
    *) die "Unsupported architecture: $(uname -m)" ;;
  esac
}

frpc_path() {
  if [ -x "$SYSTEM_FRPC" ]; then
    printf '%s\n' "$SYSTEM_FRPC"
  elif [ -x "$CACHE_FRPC" ]; then
    printf '%s\n' "$CACHE_FRPC"
  fi
}

ensure_frpc() {
  local existing
  existing="$(frpc_path || true)"
  if [ -n "$existing" ]; then
    FRPC="$existing"
    return 0
  fi

  local os arch ver tarball url tmp src
  os="$(detect_os)"; arch="$(detect_arch)"
  ver="${FRP_VERSION:-}"
  if [ -z "$ver" ]; then
    log "Resolving latest frp release..."
    ver="$(curl -fsSL https://api.github.com/repos/fatedier/frp/releases/latest \
      | grep -o '"tag_name": *"v[^"]*"' | grep -o 'v[0-9.]*' | tr -d v || true)"
    [ -n "$ver" ] || die "Could not resolve frp version. Set FRP_VERSION."
  fi
  tarball="frp_${ver}_${os}_${arch}.tar.gz"
  url="https://github.com/fatedier/frp/releases/download/v${ver}/${tarball}"
  tmp="$(mktemp -d)"
  log "Downloading frpc v${ver} (${os}/${arch})..."
  curl -fsSL "$url" -o "$tmp/$tarball" || die "Download failed: $url"
  tar -xzf "$tmp/$tarball" -C "$tmp"
  src="$tmp/frp_${ver}_${os}_${arch}"
  mkdir -p "$CACHE_DIR"
  install -m 0755 "$src/frpc" "$CACHE_FRPC"
  rm -rf "$tmp"
  FRPC="$CACHE_FRPC"
  log "Installed frpc -> $FRPC"
}

# ----------------------------------------------------------------------------
# Config
# ----------------------------------------------------------------------------
load_config() {
  # shellcheck disable=SC1090,SC1091
  [ -f "$SYSTEM_DEFAULT" ] && . "$SYSTEM_DEFAULT"
  # shellcheck disable=SC1090
  [ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"
  SERVER_ADDR="${SERVER_ADDR:-$DEFAULT_SERVER}"
  SERVER_PORT="${SERVER_PORT:-$DEFAULT_PORT}"
  DOMAIN="${DOMAIN:-$DEFAULT_DOMAIN}"
}

cmd_login() {
  mkdir -p "$CONFIG_DIR"
  load_config
  printf 'Server address [%s]: ' "$SERVER_ADDR"; read -r a; SERVER_ADDR="${a:-$SERVER_ADDR}"
  printf 'Server port [%s]: ' "$SERVER_PORT"; read -r p; SERVER_PORT="${p:-$SERVER_PORT}"
  printf 'Base domain [%s]: ' "$DOMAIN"; read -r d; DOMAIN="${d:-$DOMAIN}"
  printf 'Auth token: '; read -r t
  [ -n "$t" ] || die "Token is required."
  umask 077
  cat > "$CONFIG_FILE" <<EOF
SERVER_ADDR="$SERVER_ADDR"
SERVER_PORT="$SERVER_PORT"
DOMAIN="$DOMAIN"
TOKEN="$t"
EOF
  log "Saved config to $CONFIG_FILE"
}

require_token() {
  [ -n "${TOKEN:-}" ] || die "No auth token configured. Run:  nexory-tunnel login"
}

# ----------------------------------------------------------------------------
# Run frpc with a generated config
# ----------------------------------------------------------------------------
run_frpc() {
  local proxy_block="$1"
  local conf
  conf="$(mktemp -t frpc.XXXXXX.toml)"
  trap 'rm -f "$conf"' EXIT
  cat > "$conf" <<EOF
serverAddr = "$SERVER_ADDR"
serverPort = $SERVER_PORT
auth.token = "$TOKEN"

$proxy_block
EOF
  ensure_frpc
  # Run in foreground (not exec) so the EXIT trap removes the token-bearing temp file.
  "$FRPC" -c "$conf"
}

cmd_http() {
  local local_port="${1:-}" sub="${2:-}"
  [ -n "$local_port" ] || die "Usage: nexory-tunnel http <local_port> [subdomain]"
  require_token
  if [ -z "$sub" ]; then
    # Stable default (hostname-port) so we don't issue a brand-new TLS cert
    # on every run. Pass an explicit name to override.
    local host_slug
    host_slug="$(hostname -s 2>/dev/null || hostname)"
    host_slug="$(printf '%s' "$host_slug" | LC_ALL=C tr '[:upper:]' '[:lower:]' | LC_ALL=C tr -c 'a-z0-9' '-' | sed 's/^-*//; s/-*$//')"
    [ -n "$host_slug" ] || host_slug="dev"
    sub="${host_slug}-${local_port}"
  fi
  log "Exposing http://127.0.0.1:${local_port}  ->  https://${sub}.${DOMAIN}"
  run_frpc "$(cat <<EOF
[[proxies]]
name = "${sub}"
type = "http"
localIP = "127.0.0.1"
localPort = ${local_port}
subdomain = "${sub}"
EOF
)"
}

cmd_tcp() {
  local local_port="${1:-}" remote_port="${2:-}"
  [ -n "$local_port" ] || die "Usage: nexory-tunnel tcp <local_port> [remote_port]"
  require_token
  local name remote_line
  name="tcp-${local_port}-$(date +%s)"
  if [ -n "$remote_port" ]; then
    remote_line="remotePort = ${remote_port}"
    log "Exposing tcp 127.0.0.1:${local_port}  ->  ${DOMAIN}:${remote_port}"
  else
    remote_line="remotePort = 0   # server auto-assigns a port (see frpc output / dashboard)"
    log "Exposing tcp 127.0.0.1:${local_port}  ->  ${DOMAIN}:<auto-assigned>"
  fi
  run_frpc "$(cat <<EOF
[[proxies]]
name = "${name}"
type = "tcp"
localIP = "127.0.0.1"
localPort = ${local_port}
${remote_line}
EOF
)"
}

cmd_version() {
  ensure_frpc
  "$FRPC" --version
}

usage() {
  sed -n '2,22p' "$0" | sed 's/^# \{0,1\}//'
}

# ----------------------------------------------------------------------------
# Dispatch
# ----------------------------------------------------------------------------
main() {
  local cmd="${1:-}"; shift || true
  case "$cmd" in
    login)        cmd_login "$@" ;;
    http)         load_config; cmd_http "$@" ;;
    tcp)          load_config; cmd_tcp "$@" ;;
    version)      cmd_version ;;
    ""|-h|--help|help) usage ;;
    *) die "Unknown command: $cmd  (try: nexory-tunnel --help)" ;;
  esac
}
main "$@"
