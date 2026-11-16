#!/bin/sh

set -eu

# build script for rogsoft project
# 以 1.80.3 / Go 1.23 作为 AC68U 旧内核的待实机验证目标。
# 1.82.0 起要求 Go 1.24 / Linux >= 3.2，不能据此推断旧版已获实机验证。
MODULE="tailscale"
VERSION="1.80.3"
TITLE="Tailscale"
DESCRIPTION="基于wiregurad协议的零配置内网穿透安全组网工具！"
HOME_URL="Module_tailscale.asp"
TAGS="穿透 VPN"
AUTHOR="scjtqs2"

DIR=$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)
WORK=$(mktemp -d "$DIR/.build.XXXXXX")
trap 'rm -rf "$WORK"' EXIT
trap 'exit 1' HUP INT TERM

UPSTREAM="tailscale_${VERSION}_arm"
URL="https://pkgs.tailscale.com/stable/${UPSTREAM}.tgz"
mkdir -p "$WORK/upstream" "$WORK/package"

case "${1:-}" in
    "")
        echo "Downloading official Tailscale $VERSION (linux/arm): $URL"
        curl --fail --location --show-error --retry 2 --connect-timeout 15 \
            --max-time 300 --output "$WORK/upstream.tgz" "$URL"
        tar -xzf "$WORK/upstream.tgz" -C "$WORK/upstream" \
            "$UPSTREAM/tailscale" "$UPSTREAM/tailscaled"
        ;;
    --offline)
        # Explicit offline rebuilds require Go to inspect embedded build metadata.
        command -v go >/dev/null 2>&1 || {
            echo "Offline builds require Go (go version -m)." >&2
            exit 1
        }
        mkdir -p "$WORK/upstream/$UPSTREAM"
        cp "$DIR/$MODULE/bin/tailscale" "$DIR/$MODULE/bin/tailscaled" "$WORK/upstream/$UPSTREAM/"
        ;;
    *) echo "Usage: $0 [--offline]" >&2; exit 1 ;;
esac

# 校验架构：必须是 32 位 ARM 静态链接
for binary in tailscale tailscaled; do
    file "$WORK/upstream/$UPSTREAM/$binary" | \
        grep -q 'ELF 32-bit LSB executable, ARM,.*statically linked' || {
        echo "Unexpected binary architecture: $binary" >&2
        exit 1
    }
done

if command -v go >/dev/null 2>&1; then
    for binary in tailscale tailscaled; do
        info=$(go version -m "$WORK/upstream/$UPSTREAM/$binary")
        printf '%s\n' "$info" | grep -Eq ': go1\.23\.' &&
        printf '%s\n' "$info" | awk -v v="v$VERSION" '$1 == "mod" && $2 == "tailscale.com" && $3 == v { found=1 } END { exit !found }' &&
        printf '%s\n' "$info" | grep -q 'GOOS=linux' &&
        printf '%s\n' "$info" | grep -q 'GOARCH=arm$' &&
        printf '%s\n' "$info" | grep -q 'CGO_ENABLED=0' || {
            echo "Unexpected Tailscale version/toolchain: $binary" >&2
            exit 1
        }
    done
fi

cp -R "$DIR/$MODULE" "$WORK/package/$MODULE"
for binary in tailscale tailscaled; do
    cp "$WORK/upstream/$UPSTREAM/$binary" "$WORK/package/$MODULE/bin/$binary"
    chmod 755 "$WORK/package/$MODULE/bin/$binary"
done
chmod 755 "$WORK/package/$MODULE/scripts/tailscale_auth.sh"

# 可选：去掉调试信息以节省 /jffs 空间；实际节省量取决于上游构建。
# 需要能处理 ARM ELF 的 strip，例如 llvm-strip；也可用 STRIP=/path/to/strip 指定
STRIP_BIN=${STRIP:-$(command -v llvm-strip || true)}
if [ -n "$STRIP_BIN" ]; then
    for binary in tailscale tailscaled; do
        "$STRIP_BIN" --strip-debug "$WORK/package/$MODULE/bin/$binary"
    done
    echo "Stripped debug info with $STRIP_BIN"
else
    echo "llvm-strip not found, keeping official binaries unstripped"
fi

# 先写版本号再打包，保证安装包内外版本一致
printf '%s\n' "$VERSION" > "$WORK/package/$MODULE/version"
COPYFILE_DISABLE=1 tar -czf "$WORK/$MODULE.tar.gz" -C "$WORK/package" "$MODULE"

if command -v md5sum >/dev/null 2>&1; then
    md5value=$(md5sum "$WORK/$MODULE.tar.gz" | awk '{print $1}')
else
    md5value=$(md5 -q "$WORK/$MODULE.tar.gz")
fi
printf '%s\n%s\n' "$VERSION" "$md5value" > "$WORK/version"

DATE=$(date +%Y-%m-%d_%H:%M:%S)
cat > "$WORK/config.json.js" <<EOF
{
"version":"$VERSION",
"md5":"$md5value",
"home_url":"$HOME_URL",
"title":"$TITLE",
"description":"$DESCRIPTION",
"tags":"$TAGS",
"author":"$AUTHOR",
"link":"",
"changelog":"",
"build_date":"$DATE"
}
EOF

# 全部成功后再覆盖仓库文件；中途失败则保留原来的安装包和版本信息
for binary in tailscale tailscaled; do
    cp "$WORK/package/$MODULE/bin/$binary" "$DIR/$MODULE/bin/$binary"
done
cp "$WORK/package/$MODULE/version" "$DIR/$MODULE/version"
mv "$WORK/$MODULE.tar.gz" "$DIR/$MODULE.tar.gz"
mv "$WORK/version" "$DIR/version"
mv "$WORK/config.json.js" "$DIR/config.json.js"
echo "Build success: $DIR/$MODULE.tar.gz ($VERSION, md5: $md5value)"
