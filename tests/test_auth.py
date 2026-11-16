"""Check router handler requests with an isolated curl/LocalAPI fixture."""
import base64
import json
import os
from pathlib import Path
import subprocess
import tempfile
import sys
import unittest


REPO = Path(__file__).resolve().parents[1]


class AuthTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix="ts-auth-", dir="/tmp")
        self.root = Path(self.tmp.name)
        self.status = {"BackendState": "NeedsLogin", "AuthURL": "", "Health": []}
        self.prefs = {"RouteAll": True, "CorpDNS": False, "NetfilterMode": 0,
                      "AdvertiseRoutes": ["192.168.50.0/24"], "WantRunning": False}
        self.sock = self.root / "tailscaled.sock"
        self.sock.touch()
        self.state = self.root / "state.json"
        self.log = self.root / "requests.jsonl"
        self.mockbin = self.root / "bin"
        self.mockbin.mkdir()
        curl = self.mockbin / "curl"
        curl.write_text("#!" + sys.executable + "\n" + '''
import json, os, sys
from pathlib import Path
from urllib.parse import urlsplit
root = Path(os.environ["TEST_ROOT"])
args = sys.argv[1:]
assert args[args.index("--noproxy") + 1] == "*"
assert args[args.index("--unix-socket") + 1] == str(root / "tailscaled.sock")
assert args[args.index("--max-time") + 1] == "5"
url = urlsplit(args[-1])
assert url.hostname == "local-tailscaled.sock"
method = args[args.index("-X") + 1] if "-X" in args else "GET"
body = args[args.index("-d") + 1] if "-d" in args else ""
path = url.path + (("?" + url.query) if url.query else "")
with (root / "requests.jsonl").open("a") as f:
    f.write(json.dumps([method, path, body]) + "\\n")
state = json.loads((root / "state.json").read_text())
if path == os.environ.get("TEST_FAIL_PATH"):
    print("curl: HTTP 503", file=sys.stderr)
    sys.exit(22)
if method == "PATCH":
    patch = json.loads(body)
    assert patch == {"WantRunning": True, "WantRunningSet": True}
    state["prefs"]["WantRunning"] = patch["WantRunning"]
if method == "POST":
    state["status"]["AuthURL"] = "https://login.tailscale.com/a/test123"
(root / "state.json").write_text(json.dumps(state))
print(json.dumps(state["status"]))
''')
        curl.chmod(0o755)
        base = self.root / "base.sh"
        base.write_text('''http_response() { printf '%s' "$1"; }
dbus() { printf '%s' "${TEST_ENABLED:-1}"; }
''')
        source = (REPO / "tailscale/scripts/tailscale_auth.sh").read_text()
        source = source.replace("/koolshare/scripts/base.sh", str(base))
        for path in ("/var/run/tailscale/tailscaled.sock", "/var/run/tailscaled.sock",
                     "/tmp/tailscale/tailscaled.sock", "/tmp/tailscaled.sock"):
            source = source.replace(path, str(self.sock))
        # A plain file stands in for the Unix socket; no host sockets are opened.
        source = source.replace('[ -S "$candidate" ]', '[ -e "$candidate" ]')
        self.script = self.root / "handler.sh"
        self.script.write_text(source)

    def tearDown(self):
        self.tmp.cleanup()

    @property
    def calls(self):
        return [json.loads(line) for line in self.log.read_text().splitlines()] if self.log.exists() else []

    def call(self, action="status", enabled="1", fail_path=""):
        self.state.write_text(json.dumps({"status": self.status, "prefs": self.prefs}))
        result = subprocess.run(["sh", str(self.script), "42", action],
            env=dict(os.environ, TEST_ENABLED=enabled, TEST_ROOT=str(self.root),
                     TEST_FAIL_PATH=fail_path, PATH=str(self.mockbin) + ":" + os.environ["PATH"]), capture_output=True,
            text=True, timeout=10, check=True)
        self.prefs = json.loads(self.state.read_text())["prefs"]
        kind, payload = result.stdout.split("@@")
        payload = base64.b64decode(payload).decode()
        return kind, json.loads(payload) if kind == "ok" else payload

    def test_status_is_read_only(self):
        self.assertEqual(self.call(), ("ok", self.status))
        self.assertEqual([c[0] for c in self.calls], ["GET"])

    def test_login_preserves_network_preferences(self):
        original = dict(self.prefs)
        kind, status = self.call("login")
        self.assertEqual(kind, "ok")
        self.assertTrue(status["AuthURL"].startswith("https://login.tailscale.com/a/"))
        self.assertEqual(self.prefs, dict(original, WantRunning=True))
        self.assertEqual([tuple(c[:2]) for c in self.calls], [
            ("GET", "/localapi/v0/status?peers=false"),
            ("PATCH", "/localapi/v0/prefs"),
            ("POST", "/localapi/v0/login-interactive"),
            ("GET", "/localapi/v0/status?peers=false")])

    def test_running_node_is_not_reauthenticated(self):
        self.status["BackendState"] = "Running"
        self.call("login")
        self.assertEqual([c[0] for c in self.calls], ["GET"])

    def test_pending_link_is_reused(self):
        self.status["AuthURL"] = "https://login.tailscale.com/a/pending"
        self.assertEqual(self.call("login")[1]["AuthURL"], self.status["AuthURL"])
        self.assertEqual([c[0] for c in self.calls], ["GET"])

    def test_disabled_plugin_and_unknown_action_do_not_contact_daemon(self):
        self.assertEqual(self.call("login", enabled="0")[0], "error")
        self.assertEqual(self.call("logout")[0], "error")
        self.assertEqual(self.calls, [])

    def test_missing_socket_is_reported(self):
        self.sock.unlink()
        kind, error = self.call()
        self.assertEqual(kind, "error")
        self.assertIn("未找到 tailscaled", error)

    def test_localapi_failure_stops_login(self):
        kind, error = self.call("login", fail_path="/localapi/v0/prefs")
        self.assertEqual(kind, "error")
        self.assertIn("无法启用", error)
        self.assertFalse(any(c[0] == "POST" for c in self.calls))


if __name__ == "__main__":
    unittest.main()
