#!/bin/sh
set -eu
DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
MODULE=tailscale
VERSION=$(cat "$DIR/$MODULE/version")
CLIENT_VERSION=$(cat "$DIR/$MODULE/tailscale.version")
MODE=${1:-}
case "$MODE" in
    "") PACKAGE=tailscale.tar.gz ;;
    --full) PACKAGE=tailscale-full.tar.gz ;;
    *) echo "Usage: $0 [--full]" >&2; exit 1 ;;
esac
WORK=$(mktemp -d "$DIR/.build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' HUP INT TERM
mkdir -p "$WORK/package" "$DIR/dist"
# Exclude cached binaries even if they remain on the developer's disk.
COPYFILE_DISABLE=1 tar -cf "$WORK/source.tar" --exclude="$MODULE/bin" \
    --exclude='._*' -C "$DIR" "$MODULE"
tar -xf "$WORK/source.tar" -C "$WORK/package"
chmod 755 "$WORK/package/$MODULE/scripts/"*.sh
if [ "$MODE" = "--full" ]; then
    sh "$DIR/$MODULE/scripts/tailscale_download.sh" "$CLIENT_VERSION" \
        "$WORK/package/$MODULE/bin"
fi
COPYFILE_DISABLE=1 tar -czf "$WORK/$PACKAGE" -C "$WORK/package" "$MODULE"
mv "$WORK/$PACKAGE" "$DIR/dist/$PACKAGE"
if [ "$MODE" != "--full" ]; then
    if command -v md5sum >/dev/null 2>&1; then
        MD5=$(md5sum "$DIR/dist/$PACKAGE" | awk '{print $1}')
    else
        MD5=$(md5 -q "$DIR/dist/$PACKAGE")
    fi
    printf '%s\n%s\n' "$VERSION" "$MD5" > "$DIR/dist/version"
    cat > "$DIR/dist/config.json.js" <<EOF
{
  "version": "$VERSION",
  "md5": "$MD5",
  "home_url": "Module_tailscale.asp",
  "title": "Tailscale",
  "description": "Tailscale 内网组网工具，安装时下载官方 $CLIENT_VERSION ARM 程序",
  "tags": "穿透 VPN",
  "author": "scjtqs2 / gofunbox",
  "link": "https://github.com/gofunbox/merlin_tailscale_arm384/releases/latest/download/tailscale.tar.gz"
}
EOF
fi
echo "Built dist/$PACKAGE (plugin $VERSION, Tailscale $CLIENT_VERSION)"
