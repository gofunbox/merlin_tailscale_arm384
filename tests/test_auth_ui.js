const assert = require("assert").strict;
const fs = require("fs");
const path = require("path");
const vm = require("vm");

const elements = {};
const requests = [];
const context = {
    document: { getElementById(id) {
        if (!elements[id]) elements[id] = {
            style: {}, value: "", textContent: "", disabled: false,
            removeAttribute(name) { delete this[name]; }
        };
        return elements[id];
    } },
    dbus: { tailscale_enable: "1" },
    Base64: { decode: value => Buffer.from(value, "base64").toString("utf8") },
    $: { ajax: options => requests.push(options) },
    setTimeout: () => 1,
    clearTimeout: () => {}
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, "../tailscale/res/tailscale_auth.js"), "utf8"), context);

function respond(kind, payload) {
    const request = requests[requests.length - 1];
    request.success({ result: kind + "@@" + Buffer.from(payload).toString("base64") });
    request.complete();
}

context.tailscaleAuthRequest("login");
assert.equal(JSON.parse(requests[0].data).method, "tailscale_auth.sh");
assert.deepEqual(JSON.parse(requests[0].data).params, ["login"]);
context.tailscaleAuthRequest("login");
assert.equal(requests.length, 1, "duplicate login must be blocked while pending");
respond("ok", JSON.stringify({ BackendState: "NeedsLogin", AuthURL: "https://login.tailscale.com/a/test123" }));
assert.equal(elements.tailscale_auth_link.href, "https://login.tailscale.com/a/test123");
assert.equal(elements.tailscale_auth_url_box.style.display, "block");

context.tailscaleAuthRender({ BackendState: "NeedsLogin", AuthURL: "javascript:alert(1)" });
assert.equal(elements.tailscale_auth_link.href, undefined);
assert.equal(elements.tailscale_auth_url_box.style.display, "none");
context.tailscaleAuthRender({ BackendState: "NeedsLogin", AuthURL: "https://login.tailscale.com.evil/a/test" });
assert.equal(elements.tailscale_auth_link.href, undefined);

context.tailscaleAuthRefresh();
respond("ok", JSON.stringify({ BackendState: "Running", Health: ["<img src=x onerror=alert(1)>"] }));
assert.equal(elements.tailscale_auth_login.disabled, true);
assert.equal(elements.tailscale_auth_detail.textContent, "<img src=x onerror=alert(1)>");
assert.equal(elements.tailscale_auth_url.value, "");

context.tailscaleAuthRefresh();
respond("error", "本地接口失败");
assert.equal(elements.tailscale_auth_login.disabled, false);
assert.equal(elements.tailscale_auth_detail.textContent, "本地接口失败");
context.tailscaleAuthRefresh();
requests[requests.length - 1].success({ result: "invalid" });
requests[requests.length - 1].complete();
assert.ok(elements.tailnet_state.textContent.includes("返回异常"));

context.dbus.tailscale_enable = "0";
const count = requests.length;
context.tailscaleAuthRequest("login");
assert.equal(requests.length, count);
assert.equal(elements.tailscale_auth_login.disabled, true);
console.log("PASS: login request, duplicate suppression, authorization link, URL validation, status/error rendering, disabled state");
