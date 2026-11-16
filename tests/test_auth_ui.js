const assert = require('assert').strict;
const fs = require('fs');
const path = require('path');
const vm = require('vm');
const elements = {}, requests = [];
const context = {
  document: { getElementById(id) {
    if (!elements[id]) elements[id] = {style: {}, value: '', textContent: '',
      removeAttribute(name) { delete this[name]; }};
    return elements[id];
  } },
  dbus: { tailscale_enable: '1' },
  Base64: { decode: value => Buffer.from(value, 'base64').toString('utf8') },
  $: { ajax: options => requests.push(options) },
  setTimeout: () => 1, clearTimeout: () => {}
};
vm.createContext(context);
vm.runInContext(fs.readFileSync(path.join(__dirname, '../tailscale/res/tailscale_auth.js'), 'utf8'), context);
context.tailscaleAuthRequest('login');
context.tailscaleAuthRequest('login');
assert.equal(requests.length, 1);
assert.equal(JSON.parse(requests[0].data).method, 'tailscale_auth.sh');
function respond(kind, payload) {
  const r = requests[requests.length - 1];
  r.success({result: kind + '@@' + Buffer.from(payload).toString('base64')});
  r.complete();
}
respond('ok', JSON.stringify({BackendState: 'NeedsLogin', AuthURL: 'https://login.tailscale.com/a/test123'}));
assert.equal(elements.tailscale_auth_link.href, 'https://login.tailscale.com/a/test123');
context.tailscaleAuthRender({BackendState: 'NeedsLogin', AuthURL: 'javascript:alert(1)'});
assert.equal(elements.tailscale_auth_link.href, undefined);
context.tailscaleAuthRender({BackendState: 'NeedsLogin', AuthURL: 'https://login.tailscale.com.evil/a/test'});
assert.equal(elements.tailscale_auth_link.href, undefined);
context.tailscaleAuthRefresh();
respond('ok', JSON.stringify({BackendState: 'Running', Health: ['<img onerror=alert(1)>']}));
assert.equal(elements.tailscale_auth_login.disabled, true);
assert.equal(elements.tailscale_auth_detail.textContent, '<img onerror=alert(1)>');
context.tailscaleAuthRefresh();
respond('error', 'local interface failed');
assert.equal(elements.tailscale_auth_login.disabled, false);
assert.equal(elements.tailscale_auth_detail.textContent, 'local interface failed');
console.log('PASS: login state, duplicate requests, URL validation, safe error rendering');
