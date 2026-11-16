// Login through the existing authenticated software-center API.
var tailscaleAuthTimer = null;
var tailscaleAuthBusy = false;
var tailscaleAuthRunning = false;

function tailscaleAuthClearLink() {
    document.getElementById("tailscale_auth_link").removeAttribute("href");
    document.getElementById("tailscale_auth_url").value = "";
    document.getElementById("tailscale_auth_url_box").style.display = "none";
}

function tailscaleAuthMessage(message, detail) {
    document.getElementById("tailnet_state").textContent = message;
    document.getElementById("tailscale_auth_detail").textContent = detail || "";
}

function tailscaleAuthRender(status) {
    tailscaleAuthClearLink();
    tailscaleAuthRunning = status.BackendState === "Running";
    var messages = {
        Running: "已登录（运行中）",
        NeedsLogin: "尚未登录，点击“登录账号”获取授权链接。",
        NeedsMachineAuth: "账号授权已完成，请到 Admin console 批准这台设备。",
        Starting: "正在连接 Tailscale，请稍候。",
        Stopped: "Tailscale 已停止，请重启插件或点击“登录账号”。",
        NoState: "尚未初始化，点击“登录账号”开始。",
        InUseOtherUser: "Tailscale 正由其他用户使用，请查看运行日志。"
    };
    var message = messages[status.BackendState] || "正在读取登录状态。";
    var health = Array.isArray(status.Health) ? status.Health.join("\n") : "";
    if (status.AuthURL && !tailscaleAuthRunning) {
        // Never insert a server-provided URL as HTML or allow arbitrary schemes/hosts.
        if (/^https:\/\/(login\.)?tailscale\.com\/a\/[A-Za-z0-9_-]+(?:\?[A-Za-z0-9_=%&.~-]*)?$/.test(status.AuthURL)) {
            document.getElementById("tailscale_auth_link").href = status.AuthURL;
            document.getElementById("tailscale_auth_url").value = status.AuthURL;
            document.getElementById("tailscale_auth_url_box").style.display = "block";
            message = "等待账号授权：打开下方链接，登录你的 Tailscale 账号。";
        } else {
            message = "收到的授权地址不是预期的官方链接，请查看运行日志。";
        }
    }
    tailscaleAuthMessage(message, health);
}

function tailscaleAuthRefresh() {
    tailscaleAuthRequest("status");
}

function tailscaleAuthRequest(action) {
    if (tailscaleAuthBusy) return;
    clearTimeout(tailscaleAuthTimer);
    if (dbus["tailscale_enable"] !== "1") {
        tailscaleAuthClearLink();
        tailscaleAuthMessage("请先打开插件开关。");
        document.getElementById("tailscale_auth_login").disabled = true;
        return;
    }
    tailscaleAuthBusy = true;
    document.getElementById("tailscale_auth_login").disabled = true;
    document.getElementById("tailscale_auth_refresh").disabled = true;
    if (action === "login") {
        tailscaleAuthClearLink();
        tailscaleAuthMessage("正在获取授权链接，请稍候。");
    }
    $.ajax({
        type: "POST",
        url: "/_api/",
        cache: false,
        timeout: 25000,
        dataType: "json",
        contentType: "application/json",
        data: JSON.stringify({
            id: Math.floor(Math.random() * 100000000),
            method: "tailscale_auth.sh",
            params: [action],
            fields: ""
        }),
        success: function(response) {
            try {
                var parts = String(response.result || "").split("@@");
                if (parts.length !== 2 || !/^(ok|error)$/.test(parts[0])) {
                    throw new Error("invalid response");
                }
                var payload = Base64.decode(parts[1]);
                if (parts[0] === "error") {
                    tailscaleAuthRunning = false;
                    tailscaleAuthClearLink();
                    tailscaleAuthMessage("暂时无法获取登录状态。", payload);
                } else {
                    tailscaleAuthRender(JSON.parse(payload));
                }
            } catch (error) {
                tailscaleAuthRunning = false;
                tailscaleAuthClearLink();
                tailscaleAuthMessage("登录接口返回异常，请确认已安装新版插件并刷新页面。");
            }
        },
        error: function() {
            tailscaleAuthRunning = false;
            tailscaleAuthClearLink();
            tailscaleAuthMessage("读取登录状态超时或失败，请查看 tailscaled 运行日志。");
        },
        complete: function() {
            tailscaleAuthBusy = false;
            document.getElementById("tailscale_auth_login").disabled = tailscaleAuthRunning;
            document.getElementById("tailscale_auth_refresh").disabled = false;
            tailscaleAuthTimer = setTimeout(tailscaleAuthRefresh, 5000);
        }
    });
}
