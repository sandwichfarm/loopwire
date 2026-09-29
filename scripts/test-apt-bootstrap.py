#!/usr/bin/env python3
"""Exercise the bootstrap with real HTTPS/GnuPG and isolated /etc trees."""
import functools
import http.server
import os
from pathlib import Path
import shutil
import ssl
import subprocess
import tempfile
import threading
import unittest


SCRIPT = Path(__file__).resolve().with_name("setup-apt-repository.sh")


def run(*args, **kwargs):
    return subprocess.run(args, check=True, capture_output=True, text=True, **kwargs)


class BootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-apt-bootstrap-")
        cls.work = Path(cls.temporary.name)
        cls.home = cls.work / "gnupg"
        cls.home.mkdir(mode=0o700)
        run("gpg", "--batch", "--homedir", str(cls.home), "--pinentry-mode", "loopback", "--passphrase", "",
            "--quick-generate-key", "Loopwire bootstrap fixture <fixture@example.invalid>", "rsa2048", "sign", "1d")
        keys = run("gpg", "--homedir", str(cls.home), "--with-colons", "--list-keys").stdout
        cls.fingerprint = next(line.split(":")[9] for line in keys.splitlines() if line.startswith("fpr:"))
        cls.public = run("gpg", "--homedir", str(cls.home), "--armor", "--export", cls.fingerprint).stdout
        cls.web = cls.work / "web"
        (cls.web / "keys").mkdir(parents=True)
        (cls.web / "keys" / f"{cls.fingerprint}.asc").write_text(cls.public)
        (cls.web / "keys" / f"{'A' * 40}.asc").write_text(cls.public)
        cert, key = cls.work / "cert.pem", cls.work / "key.pem"
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
            "-keyout", str(key), "-out", str(cert))
        cls.requests = []

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                cls.requests.append(self.path)
                super().do_GET()

        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(Handler, directory=str(cls.web)))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"https://127.0.0.1:{cls.server.server_port}"
        cls.binary = cls.work / "bin"
        cls.binary.mkdir()
        dpkg = cls.binary / "dpkg"
        dpkg.write_text('#!/bin/sh\nprintf "%s\\n" "${TEST_ARCH:-amd64}"\n')
        dpkg.chmod(0o755)
        cls.environment = {**os.environ, "PATH": f"{cls.binary}:{os.environ['PATH']}", "CURL_CA_BUNDLE": str(cert)}

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        subprocess.run(["gpgconf", "--homedir", str(cls.home), "--kill", "all"], check=False,
                       stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        cls.temporary.cleanup()

    def setUp(self):
        self.root = self.work / "root"
        shutil.rmtree(self.root, ignore_errors=True)
        (self.root / "etc").mkdir(parents=True)
        self.os_release("ubuntu", "24.04")
        self.source = self.root / "etc/apt/sources.list.d/loopwire.sources"
        self.key = self.root / f"etc/apt/keyrings/loopwire-{self.fingerprint}.asc"
        self.requests.clear()

    def os_release(self, identity, version):
        (self.root / "etc/os-release").write_text(f'ID={identity}\nVERSION_ID="{version}"\n')

    def invoke(self, *args, fingerprint=None, url=None, env=None):
        return subprocess.run([
            "bash", str(SCRIPT), "--root", str(self.root), "--base-url", url or self.url,
            "--fingerprint", fingerprint or self.fingerprint, *args,
        ], env={**self.environment, **(env or {})}, capture_output=True, text=True)

    def test_supported_suites_and_idempotence(self):
        for identity, version, suite in [("ubuntu", "24.04", "ubuntu-24.04"), ("debian", "13", "debian-13")]:
            with self.subTest(suite=suite):
                self.os_release(identity, version)
                result = self.invoke()
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertIn(f"Suites: {suite}\n", self.source.read_text())
                self.assertIn(f"Signed-By: /etc/apt/keyrings/loopwire-{self.fingerprint}.asc", self.source.read_text())
                self.assertEqual(self.key.read_text(), self.public)
                self.assertEqual(self.key.stat().st_mode & 0o777, 0o644)
                source_bytes = self.source.read_bytes()
                again = self.invoke()
                self.assertEqual(again.returncode, 0, again.stderr)
                self.assertEqual(self.source.read_bytes(), source_bytes)

    def test_dry_run_has_no_network_or_writes(self):
        result = self.invoke("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests, [])
        self.assertFalse(self.source.exists())
        self.assertFalse(self.key.exists())

    def test_wrong_fingerprint_preserves_existing_configuration(self):
        self.assertEqual(self.invoke().returncode, 0)
        before = self.source.read_bytes()
        result = self.invoke(fingerprint="A" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("does not match", result.stderr)
        self.assertEqual(self.source.read_bytes(), before)
        self.assertEqual(self.key.read_text(), self.public)

    def test_tls_authentication_required(self):
        result = self.invoke(env={"CURL_CA_BUNDLE": str(self.work / "absent-ca.pem")})
        self.assertNotEqual(result.returncode, 0)
        self.assertFalse(self.source.exists())

    def test_bad_urls_rejected_without_network(self):
        for url in ["http://example.invalid", "https://user:pass@example.invalid", "https://example.invalid/#fragment",
                    "https://example.invalid/?query=x", "https://example.invalid/\ninjected", "https://example.invalid:99999"]:
            with self.subTest(url=url):
                self.assertNotEqual(self.invoke(url=url).returncode, 0)
        self.assertEqual(self.requests, [])
        self.assertFalse(self.source.exists())

    def test_unsupported_distribution_and_architecture(self):
        self.os_release("ubuntu", "22.04")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.os_release("ubuntu", "24.04")
        self.assertNotEqual(self.invoke(env={"TEST_ARCH": "arm64"}).returncode, 0)
        self.assertEqual(self.requests, [])

    def test_os_release_is_never_executed(self):
        sentinel = self.work / "must-not-exist"
        self.os_release(f'"$(touch {sentinel})"', "24.04")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(sentinel.exists())

    def test_unmanaged_source_preserved(self):
        self.source.parent.mkdir(parents=True)
        self.source.write_text("# Maintainer-owned source\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertNotEqual(self.invoke("--remove").returncode, 0)
        self.assertEqual(self.source.read_text(), "# Maintainer-owned source\n")

    def test_source_symlink_rejected(self):
        self.source.parent.mkdir(parents=True)
        destination = self.root / "unrelated"
        destination.write_text("keep")
        self.source.symlink_to(destination)
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertEqual(destination.read_text(), "keep")

    def test_symlinked_parent_cannot_escape_offline_root(self):
        outside = self.work / "outside"
        outside.mkdir(exist_ok=True)
        for relative in ["etc/apt", "etc/apt/sources.list.d", "etc/apt/keyrings"]:
            with self.subTest(relative=relative):
                shutil.rmtree(self.root / "etc/apt", ignore_errors=True)
                parent = self.root / relative
                parent.parent.mkdir(parents=True, exist_ok=True)
                parent.symlink_to(outside, target_is_directory=True)
                try:
                    result = self.invoke()
                    self.assertNotEqual(result.returncode, 0)
                    self.assertEqual(list(outside.iterdir()), [])
                finally:
                    parent.unlink(missing_ok=True)
                    shutil.rmtree(outside)
                    outside.mkdir()

    def test_remove_is_idempotent_and_preserves_other_sources(self):
        self.assertEqual(self.invoke().returncode, 0)
        other = self.source.with_name("unrelated.sources")
        other.write_text("keep")
        for _ in range(2):
            result = self.invoke("--remove")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.source.exists())
        self.assertFalse(self.key.exists())
        self.assertEqual(other.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
