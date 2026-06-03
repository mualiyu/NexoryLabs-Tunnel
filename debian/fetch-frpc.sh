#!/bin/bash
# Download frpc for the target architecture during package build.
set -euo pipefail

FRP_VERSION="${FRP_VERSION:-0.69.1}"
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
OUT="$ROOT/build/frpc"

arch="$(dpkg-architecture -qDEB_BUILD_GNU_CPU)"
case "$arch" in
  amd64) frp_arch=amd64 ;;
  arm64) frp_arch=arm64 ;;
  *)
    echo "Unsupported architecture for frpc bundle: $arch" >&2
    exit 1
    ;;
esac

tarball="frp_${FRP_VERSION}_linux_${frp_arch}.tar.gz"
url="https://github.com/fatedier/frp/releases/download/v${FRP_VERSION}/${tarball}"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

echo "Fetching frpc v${FRP_VERSION} (${frp_arch})..."
curl -fsSL "$url" -o "$tmp/$tarball"
tar -xzf "$tmp/$tarball" -C "$tmp"

mkdir -p "$(dirname "$OUT")"
install -m 0755 "$tmp/frp_${FRP_VERSION}_linux_${frp_arch}/frpc" "$OUT"
echo "Bundled frpc -> $OUT"
