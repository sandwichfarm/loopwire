#!/usr/bin/env python3
import contextlib
import functools
import hashlib
import http.server
import importlib.util
import io
import json
from pathlib import Path
import ssl
import subprocess
import sys
import tempfile
import threading
import unittest
from unittest.mock import patch


SCRIPT = Path(__file__).with_name("verify-rpm-public.py")
spec = importlib.util.spec_from_file_location("rpm_public", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-rpm-public-")
        cls.root = Path(cls.temporary.name)
        cls.web = cls.root / "web"
        cls.web.mkdir()
        cls.cert, key = cls.root / "cert.pem", cls.root / "key.pem"
        subprocess.run(["openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
                        "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
                        "-keyout", str(key), "-out", str(cls.cert)], check=True, capture_output=True)

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *_args):
                pass

        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(Handler, directory=str(cls.web)))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cls.cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        threading.Thread(target=cls.server.serve_forever, daemon=True).start()
        cls.url = f"https://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.temporary.cleanup()

    def setUp(self):
        payload = b"signed rpm bytes"
        (self.web / "packages").mkdir(exist_ok=True)
        (self.web / "packages/loopwire.rpm").write_bytes(payload)
        manifest = json.dumps({"target": {"distribution": "fedora", "release": "44", "architecture": "x86_64"},
                               "revision": "a" * 64, "files": [{
            "path": "packages/loopwire.rpm", "size": len(payload), "sha256": hashlib.sha256(payload).hexdigest()}]})
        (self.root / "repository-manifest.json").write_text(manifest)
        (self.web / "repository-manifest.json").write_text(manifest)
        self.output = self.root / "channel.json"
        self.output.unlink(missing_ok=True)

    def invoke(self, *extra, verifier_error=None):
        args = [str(SCRIPT), "--repository", str(self.root), "--public-key", str(self.root / "key.asc"),
                "--fingerprint", "A" * 40, "--base-url", self.url]
        if "--output" not in extra:
            args += ["--ca-file", str(self.cert)]
        args += extra
        trust = ssl.create_default_context(cafile=str(self.cert))
        with patch.object(sys, "argv", args), patch.object(module.subprocess, "run") as verifier, \
                patch.object(module.ssl, "create_default_context", return_value=trust), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            if verifier_error:
                verifier.side_effect = verifier_error
            module.main()
            verifier.assert_called_once()
            self.assertTrue(verifier.call_args.kwargs["check"])
            return json.loads(output.getvalue())

    def test_exact_public_bytes_produce_fedora_record(self):
        result = self.invoke("--output", str(self.output), "--proof-url",
                             "https://github.com/sandwichfarm/loopwire/actions/runs/123")
        self.assertEqual(result["files"], 2)
        record = json.loads(self.output.read_text())
        self.assertEqual(record["target"], "fedora-44")
        self.assertEqual(record["baseUrl"], self.url)

    def test_package_or_manifest_tamper_fails(self):
        for path in [self.web / "packages/loopwire.rpm", self.web / "repository-manifest.json"]:
            with self.subTest(path=path.name):
                before = path.read_bytes()
                path.write_bytes(b"tampered")
                with self.assertRaises(ValueError):
                    self.invoke()
                path.write_bytes(before)

    def test_local_signature_failure_prevents_network(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(verifier_error=subprocess.CalledProcessError(1, "verify"))

    def test_custom_ca_cannot_activate(self):
        with self.assertRaisesRegex(ValueError, "custom-CA fixture"):
            self.invoke("--output", str(self.output), "--ca-file", str(self.cert), "--proof-url",
                        "https://github.com/sandwichfarm/loopwire/actions/runs/123")

    def test_invalid_url_fingerprint_and_proof_fail(self):
        for args in [("--base-url", "http://example.invalid"), ("--fingerprint", "short"),
                     ("--output", str(self.output), "--proof-url", "https://example.invalid/run/1")]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.invoke(*args)

    def test_wrong_target_fails(self):
        manifest = json.loads((self.root / "repository-manifest.json").read_text())
        manifest["target"] = {"distribution": "opensuse", "release": "tumbleweed", "architecture": "x86_64"}
        (self.root / "repository-manifest.json").write_text(json.dumps(manifest))
        with self.assertRaisesRegex(ValueError, "Fedora"):
            self.invoke()


if __name__ == "__main__":
    unittest.main()
