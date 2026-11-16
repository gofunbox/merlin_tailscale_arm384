#!/bin/sh

# Called by the authenticated software-center API: $1=request ID, $2=action.
. /koolshare/scripts/base.sh

reply() {
    payload=$(printf '%s' "$2" | base64 | tr -d '\r\n')
    http_response "$1@@$payload"
    exit 0
}

action=${2:-status}
case "$action" in
    status|login) ;;
    *) reply error "不支持的登录操作。" ;;
esac

[ "$(dbus get tailscale_enable)" = "1" ] || reply error "请先打开插件开关。"

# Only contact the local Unix socket. No extra web server or open TCP port.
socket=
for candidate in /var/run/tailscale/tailscaled.sock /var/run/tailscaled.sock \
    /tmp/tailscale/tailscaled.sock /tmp/tailscaled.sock; do
    if [ -S "$candidate" ]; then
        socket=$candidate
        break
    fi
done
[ -n "$socket" ] || reply error "未找到 tailscaled 本地接口，请检查运行日志并重启插件。"

local_request() {
    curl --silent --show-error --fail --noproxy '*' --max-time 5 \
        --unix-socket "$socket" "$@"
}

status=$(local_request 'http://local-tailscaled.sock/localapi/v0/status?peers=false' 2>&1) || \
    reply error "无法读取 tailscaled 状态：$status"

if [ "$action" = "login" ]; then
    # An active node or an outstanding authorization URL needs no new login.
    # Avoid `tailscale login`: in 1.80.3 it switches to an empty profile.
    if ! printf '%s' "$status" | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"|"AuthURL"[[:space:]]*:[[:space:]]*"https://'; then
        # Change only WantRunning; preserve existing subnet/DNS/firewall settings.
        result=$(local_request -X PATCH -H 'Content-Type: application/json' \
            -d '{"WantRunning":true,"WantRunningSet":true}' \
            'http://local-tailscaled.sock/localapi/v0/prefs' 2>&1) || \
            reply error "无法启用 Tailscale：$result"
        result=$(local_request -X POST \
            'http://local-tailscaled.sock/localapi/v0/login-interactive' 2>&1) || \
            reply error "无法发起登录：$result"
        status=$(local_request 'http://local-tailscaled.sock/localapi/v0/status?peers=false' 2>&1) || \
            reply error "已发起登录，但读取状态失败：$status"
    fi
fi

reply ok "$status"
