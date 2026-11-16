#!/bin/sh
# Shared by the router installer and the optional full-package build.
set -eu
VERSION=${1:?Tailscale version required}
DEST=${2:?Destination directory required}
case "$VERSION" in
    1.80.3) ;;
    *) echo "Unsupported Tailscale version: $VERSION" >&2; exit 1 ;;
esac
mkdir -p "$DEST"
WORK=$(mktemp -d "$DEST/.download.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' HUP INT TERM
UPSTREAM="tailscale_${VERSION}_arm"
URL="https://pkgs.tailscale.com/stable/${UPSTREAM}.tgz"
echo "下载 Tailscale 官方 Linux ARM $VERSION：$URL"
curl --fail --location --show-error --retry 2 --connect-timeout 15 \
    --max-time 180 --output "$WORK/upstream.tgz" "$URL"
tar -xzf "$WORK/upstream.tgz" -C "$WORK" \
    "$UPSTREAM/tailscale" "$UPSTREAM/tailscaled"
for binary in tailscale tailscaled; do
    FILE="$WORK/$UPSTREAM/$binary"
    # ELF32, little endian, ARM; uses BusyBox-compatible commands on the router.
    MAGIC=$(dd if="$FILE" bs=1 count=7 2>/dev/null | od -An -tx1 | tr -d ' \r\n')
    MACHINE=$(dd if="$FILE" bs=1 skip=18 count=2 2>/dev/null | od -An -tx1 | tr -d ' \r\n')
    if [ "$MAGIC" != "7f454c46010101" ] || [ "$MACHINE" != "2800" ]; then
        echo "下载的 $binary 不是预期的 32 位 ARM 程序。" >&2
        exit 1
    fi
    chmod 755 "$FILE"
done
for binary in tailscale tailscaled; do
    mv "$WORK/$UPSTREAM/$binary" "$DEST/$binary"
done
