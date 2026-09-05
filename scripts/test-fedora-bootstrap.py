#!/usr/bin/env python3
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


SCRIPT = Path(__file__).with_name("setup-fedora-repository.sh")


def run(*args):
    return subprocess.run(args, check=True, capture_output=True, text=True)


class BootstrapTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-fedora-bootstrap-")
        cls.work = Path(cls.temporary.name)
        cls.home = cls.work / "gnupg"
        cls.home.mkdir(mode=0o700)
        run("gpg", "--batch", "--homedir", str(cls.home), "--pinentry-mode", "loopback", "--passphrase", "",
            "--quick-generate-key", "Loopwire Fedora fixture <fixture@example.invalid>", "rsa2048", "sign", "1d")
        listing = run("gpg", "--homedir", str(cls.home), "--with-colons", "--list-keys").stdout
        cls.fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
        cls.public = run("gpg", "--homedir", str(cls.home), "--armor", "--export", cls.fingerprint).stdout
        cls.web = cls.work / "web"
        (cls.web / "keys").mkdir(parents=True)
        (cls.web / "keys" / f"{cls.fingerprint}.asc").write_text(cls.public)
        (cls.web / "keys" / f"{'A' * 40}.asc").write_text(cls.public)
        cert, key = cls.work / "cert.pem", cls.work / "key.pem"
        run("openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1", "-subj", "/CN=127.0.0.1",
            "-addext", "subjectAltName=IP:127.0.0.1", "-keyout", str(key), "-out", str(cert))
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
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"https://127.0.0.1:{cls.server.server_port}"
        cls.binary = cls.work / "bin"
        cls.binary.mkdir()
        rpm = cls.binary / "rpm"
        rpm.write_text('#!/bin/sh\nprintf "%s\\n" "${TEST_ARCH:-x86_64}"\n')
        rpm.chmod(0o755)
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
        (self.root / "etc/os-release").write_text('ID=fedora\nVERSION_ID="44"\n')
        self.repo = self.root / "etc/yum.repos.d/loopwire.repo"
        self.key = self.root / f"etc/pki/rpm-gpg/RPM-GPG-KEY-loopwire-{self.fingerprint}"
        self.requests.clear()

    def invoke(self, *args, fingerprint=None, url=None, env=None):
        return subprocess.run([
            "bash", str(SCRIPT), "--root", str(self.root), "--base-url", url or self.url,
            "--fingerprint", fingerprint or self.fingerprint, *args,
        ], env={**self.environment, **(env or {})}, capture_output=True, text=True)

    def test_configuration_signature_checks_and_idempotence(self):
        for _ in range(2):
            result = self.invoke()
            self.assertEqual(result.returncode, 0, result.stderr)
        text = self.repo.read_text()
        for line in [f"baseurl={self.url}", "gpgcheck=1", "repo_gpgcheck=1", "sslverify=1",
                     f"gpgkey=file:///etc/pki/rpm-gpg/RPM-GPG-KEY-loopwire-{self.fingerprint}"]:
            self.assertIn(line, text)
        self.assertEqual(self.key.read_text(), self.public)
        self.assertEqual(self.key.stat().st_mode & 0o777, 0o644)

    def test_dry_run_has_no_network_or_writes(self):
        result = self.invoke("--dry-run")
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(self.requests, [])
        self.assertFalse(self.repo.exists())

    def test_wrong_fingerprint_preserves_existing_configuration(self):
        self.assertEqual(self.invoke().returncode, 0)
        before = self.repo.read_bytes()
        result = self.invoke(fingerprint="A" * 40)
        self.assertNotEqual(result.returncode, 0)
        self.assertEqual(self.repo.read_bytes(), before)

    def test_bad_urls_and_wrong_platform_fail_before_network(self):
        for url in ["http://example.invalid", "https://user:pass@example.invalid", "https://example.invalid/?",
                    "https://example.invalid/#", "https://example.invalid/\ninjected"]:
            with self.subTest(url=url):
                self.assertNotEqual(self.invoke(url=url).returncode, 0)
        (self.root / "etc/os-release").write_text('ID=fedora\nVERSION_ID="43"\n')
        self.assertNotEqual(self.invoke().returncode, 0)
        (self.root / "etc/os-release").write_text('ID=fedora\nVERSION_ID="44"\n')
        self.assertNotEqual(self.invoke(env={"TEST_ARCH": "aarch64"}).returncode, 0)
        self.assertEqual(self.requests, [])

    def test_os_release_is_data(self):
        sentinel = self.work / "must-not-exist"
        (self.root / "etc/os-release").write_text(f'ID="$(touch {sentinel})"\nVERSION_ID=44\n')
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertFalse(sentinel.exists())

    def test_unmanaged_and_symlinked_paths_are_preserved(self):
        self.repo.parent.mkdir(parents=True)
        self.repo.write_text("# other owner\n")
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertNotEqual(self.invoke("--remove").returncode, 0)
        self.repo.unlink()
        outside = self.work / "outside"
        outside.mkdir(exist_ok=True)
        (self.root / "etc/yum.repos.d").rmdir()
        (self.root / "etc/yum.repos.d").symlink_to(outside, target_is_directory=True)
        self.assertNotEqual(self.invoke().returncode, 0)
        self.assertEqual(list(outside.iterdir()), [])

    def test_remove_is_idempotent_and_preserves_other_repositories(self):
        self.assertEqual(self.invoke().returncode, 0)
        other = self.repo.with_name("unrelated.repo")
        other.write_text("keep")
        for _ in range(2):
            result = self.invoke("--remove")
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertFalse(self.repo.exists())
        self.assertFalse(self.key.exists())
        self.assertEqual(other.read_text(), "keep")


if __name__ == "__main__":
    unittest.main()
