import hashlib
import io
import json
import os
import re
from pathlib import Path
import shutil
import subprocess
import tarfile
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class PackagingTest(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory(prefix='merlin-package-')
        self.root = Path(self.tmp.name) / 'project with spaces'
        shutil.copytree(ROOT / 'tailscale', self.root / 'tailscale')
        shutil.copy2(ROOT / 'build.sh', self.root / 'build.sh')
        self.mock = Path(self.tmp.name) / 'mockbin'
        self.mock.mkdir()
        curl = self.mock / 'curl'
        curl.write_text('''#!/bin/sh
set -eu
[ "${TEST_DOWNLOAD_FAIL:-0}" = 0 ] || exit 6
out=
while [ "$#" -gt 0 ]; do
 case "$1" in --output) out=$2; shift ;; esac
 last=$1
 shift
done
[ "$last" = "https://pkgs.tailscale.com/stable/tailscale_1.80.3_arm.tgz" ]
cp "$TEST_ARCHIVE" "$out"
''')
        curl.chmod(0o755)
        self.archive = Path(self.tmp.name) / 'official-fixture.tgz'
        self.header = bytearray(64)
        self.header[:7] = bytes.fromhex('7f454c46010101')
        self.header[18:20] = bytes.fromhex('2800')
        self.make_archive(bytes(self.header))
        self.env = dict(os.environ, PATH=str(self.mock) + ':' + os.environ['PATH'],
                        TEST_ARCHIVE=str(self.archive))

    def tearDown(self):
        self.tmp.cleanup()

    def make_archive(self, payload):
        with tarfile.open(self.archive, 'w:gz') as t:
            for name in ('tailscale', 'tailscaled'):
                member = tarfile.TarInfo('tailscale_1.80.3_arm/' + name)
                member.size = len(payload)
                t.addfile(member, io.BytesIO(payload))

    def build(self, *args, fail=False):
        return subprocess.run(['sh', str(self.root / 'build.sh'), *args],
                              cwd=self.tmp.name, env=dict(self.env, TEST_DOWNLOAD_FAIL='1' if fail else '0'),
                              capture_output=True, text=True)

    def test_small_package_excludes_cached_binaries_and_needs_no_network(self):
        cache = self.root / 'tailscale/bin'
        cache.mkdir(exist_ok=True)
        (cache / 'tailscale').write_bytes(b'cached-large-file' * 10000)
        result = self.build(fail=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        package = self.root / 'dist/tailscale.tar.gz'
        self.assertLess(package.stat().st_size, 200_000)
        with tarfile.open(package) as t:
            self.assertFalse(any(m.name.startswith('tailscale/bin') for m in t))
            self.assertIsNotNone(t.getmember('tailscale/scripts/tailscale_download.sh'))
            self.assertEqual(t.extractfile('tailscale/tailscale.version').read(), b'1.80.3\n')
        md5 = hashlib.md5(package.read_bytes()).hexdigest()
        self.assertEqual((self.root / 'dist/version').read_text().splitlines(), ['1.80.3.1', md5])
        self.assertEqual(json.loads((self.root / 'dist/config.json.js').read_text())['md5'], md5)
        self.assertFalse((self.root / 'tailscale.tar.gz').exists())

    def test_full_package_and_small_metadata_are_separate(self):
        self.assertEqual(self.build().returncode, 0)
        metadata = (self.root / 'dist/version').read_bytes()
        result = self.build('--full')
        self.assertEqual(result.returncode, 0, result.stderr)
        with tarfile.open(self.root / 'dist/tailscale-full.tar.gz') as t:
            for name in ('tailscale', 'tailscaled'):
                m = t.getmember('tailscale/bin/' + name)
                self.assertEqual(t.extractfile(m).read(), bytes(self.header))
                self.assertEqual(m.mode & 0o111, 0o111)
        self.assertEqual((self.root / 'dist/version').read_bytes(), metadata)

    def test_failed_download_keeps_previous_full_package(self):
        self.assertEqual(self.build('--full').returncode, 0)
        package = self.root / 'dist/tailscale-full.tar.gz'
        previous = package.read_bytes()
        self.assertNotEqual(self.build('--full', fail=True).returncode, 0)
        self.assertEqual(package.read_bytes(), previous)
        self.assertEqual(list(self.root.glob('.build.*')), [])

    def test_wrong_architecture_does_not_replace_existing_runtime(self):
        self.make_archive(b'wrong architecture')
        dest = Path(self.tmp.name) / 'runtime'
        dest.mkdir()
        (dest / 'tailscale').write_text('existing')
        result = subprocess.run(['sh', str(self.root / 'tailscale/scripts/tailscale_download.sh'),
                                 '1.80.3', str(dest)], env=self.env, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual((dest / 'tailscale').read_text(), 'existing')
        self.assertFalse((dest / 'tailscaled').exists())
        self.assertEqual(list(dest.glob('.download.*')), [])

    def test_installer_prepares_runtime_before_stopping_existing_plugin(self):
        source = (self.root / 'tailscale/install.sh').read_text()
        body = source.split('install_now(){', 1)[1]
        self.assertLess(body.index('prepare_binaries'), body.index('/koolshare/scripts/tailscale_config stop'))
        self.assertLess(body.index('prepare_binaries'), body.index('rm -rf /koolshare/bin/tailscale'))

    def prepare(self):
        source = (self.root / 'tailscale/install.sh').read_text()
        function = re.search(r'prepare_binaries\(\)\{.*?\n\}', source, re.S).group()
        runner = 'DIR="$TEST_MODULE"\nDOWNLOAD_DIR=\nBIN_DIR=\n'
        runner += 'trap \'[ -z "$DOWNLOAD_DIR" ] || rm -rf "$DOWNLOAD_DIR"\' EXIT\n'
        runner += 'echo_date() { echo "$@"; }\n' + function + '\nprepare_binaries\n'
        return subprocess.run(['bash', '-c', runner], env=dict(self.env, TEST_MODULE=str(self.root / 'tailscale')),
                              capture_output=True, text=True)

    def test_installer_accepts_full_package_without_downloading(self):
        cache = self.root / 'tailscale/bin'
        cache.mkdir(exist_ok=True)
        for name in ('tailscale', 'tailscaled'):
            (cache / name).write_text('#!/bin/sh\necho 1.80.3\n')
        result = self.prepare()
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertIn('完整离线包', result.stdout)

    def test_installer_rejects_unrunnable_or_wrong_version(self):
        cache = self.root / 'tailscale/bin'
        cache.mkdir(exist_ok=True)
        for name in ('tailscale', 'tailscaled'):
            (cache / name).write_text('#!/bin/sh\necho 1.76.6\n')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('现有插件保持不变', result.stdout)

    def test_installer_aborts_on_download_failure(self):
        shutil.rmtree(self.root / 'tailscale/bin', ignore_errors=True)
        (self.root / 'tailscale/scripts/tailscale_download.sh').write_text('#!/bin/sh\nexit 6\n')
        result = self.prepare()
        self.assertNotEqual(result.returncode, 0)
        self.assertIn('下载失败，现有插件保持不变', result.stdout)


if __name__ == '__main__':
    unittest.main()
