#!/bin/sh
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
socket=
for candidate in /var/run/tailscale/tailscaled.sock /var/run/tailscaled.sock \
    /tmp/tailscale/tailscaled.sock /tmp/tailscaled.sock; do
    if [ -S "$candidate" ]; then socket=$candidate; break; fi
done
[ -n "$socket" ] || reply error "未找到 tailscaled 本地接口，请检查运行日志并重启插件。"
local_request() {
    curl --silent --show-error --fail --noproxy '*' --max-time 5 \
        --unix-socket "$socket" "$@"
}
status=$(local_request 'http://local-tailscaled.sock/localapi/v0/status?peers=false' 2>&1) || \
    reply error "无法读取 tailscaled 状态：$status"
if [ "$action" = "login" ]; then
    # `tailscale login` in 1.80.3 switches to an empty profile: use LocalAPI instead.
    if ! printf '%s' "$status" | grep -Eq '"BackendState"[[:space:]]*:[[:space:]]*"Running"|"AuthURL"[[:space:]]*:[[:space:]]*"https://'; then
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
