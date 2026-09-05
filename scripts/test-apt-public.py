#!/usr/bin/env python3
"""Test public byte verification and activation output independently of the signed-chain verifier."""
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

SCRIPT = Path(__file__).with_name("verify-apt-public.py")
spec = importlib.util.spec_from_file_location("apt_public", SCRIPT)
module = importlib.util.module_from_spec(spec)
spec.loader.exec_module(module)


class PublicTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-apt-public-")
        cls.root = Path(cls.temporary.name)
        cls.web = cls.root / "web"
        cls.web.mkdir()
        cls.cert, key = cls.root / "cert.pem", cls.root / "key.pem"
        subprocess.run([
            "openssl", "req", "-x509", "-newkey", "rsa:2048", "-nodes", "-days", "1",
            "-subj", "/CN=127.0.0.1", "-addext", "subjectAltName=IP:127.0.0.1",
            "-keyout", str(key), "-out", str(cls.cert),
        ], check=True, capture_output=True)
        cls.requests = []

        class Handler(http.server.SimpleHTTPRequestHandler):
            def log_message(self, *_args):
                pass

            def do_GET(self):
                cls.requests.append(self.path)
                if self.path.startswith("/redirect/"):
                    self.send_response(302)
                    self.send_header("Location", "/must-not-follow")
                    self.end_headers()
                else:
                    super().do_GET()

        cls.server = http.server.ThreadingHTTPServer(
            ("127.0.0.1", 0), functools.partial(Handler, directory=str(cls.web)))
        context = ssl.SSLContext(ssl.PROTOCOL_TLS_SERVER)
        context.load_cert_chain(cls.cert, key)
        cls.server.socket = context.wrap_socket(cls.server.socket, server_side=True)
        cls.thread = threading.Thread(target=cls.server.serve_forever, daemon=True)
        cls.thread.start()
        cls.url = f"https://127.0.0.1:{cls.server.server_port}"

    @classmethod
    def tearDownClass(cls):
        cls.server.shutdown()
        cls.server.server_close()
        cls.temporary.cleanup()

    def setUp(self):
        self.requests.clear()
        (self.web / "payload").write_bytes(b"expected package bytes")
        (self.root / "repository-manifest.json").write_text(json.dumps({
            "revision": "a" * 64,
            "files": [{"path": "payload", "size": 22, "sha256": hashlib.sha256(b"expected package bytes").hexdigest()}],
        }))
        self.output = self.root / "activation.json"
        self.output.unlink(missing_ok=True)

    def invoke(self, *extra, verifier_error=None):
        args = [str(SCRIPT), "--repository", str(self.root), "--public-key", str(self.root / "trusted.asc"),
                "--fingerprint", "A" * 40, "--base-url", self.url]
        if "--output" not in extra:
            args += ["--ca-file", str(self.cert)]
        args += extra
        trust = ssl.create_default_context(cafile=str(self.cert))
        with patch.object(sys, "argv", args), patch.object(module.subprocess, "run") as verify, \
                patch.object(module.ssl, "create_default_context", return_value=trust), \
                contextlib.redirect_stdout(io.StringIO()) as output:
            if verifier_error:
                verify.side_effect = verifier_error
            module.main()
            verify.assert_called_once()
            self.assertTrue(verify.call_args.kwargs["check"])
            self.assertIn("--fingerprint", verify.call_args.args[0])
            self.assertIn(str(self.root / "trusted.asc"), verify.call_args.args[0])
            return json.loads(output.getvalue())

    def test_verified_bytes_produce_activation_record(self):
        result = self.invoke("--output", str(self.output), "--proof-url", "https://github.com/sandwichfarm/loopwire/actions/runs/123")
        self.assertEqual(result["files"], 1)
        record = json.loads(self.output.read_text())
        self.assertEqual(record["status"], "verified")
        self.assertEqual(record["baseUrl"], self.url)
        self.assertEqual(record["revision"], "a" * 64)
        self.assertEqual(record["signingFingerprint"], "A" * 40)
        self.assertIn("verifiedAt", record)

    def test_remote_tamper_never_overwrites_activation(self):
        self.output.write_text("previous activation")
        (self.web / "payload").write_bytes(b"changed package bytes!")
        with self.assertRaises(ValueError):
            self.invoke("--output", str(self.output), "--proof-url", "https://github.com/sandwichfarm/loopwire/actions/runs/123")
        self.assertEqual(self.output.read_text(), "previous activation")

    def test_missing_file_fails(self):
        (self.web / "payload").unlink()
        with self.assertRaisesRegex(ValueError, "HTTP 404"):
            self.invoke()
        self.assertFalse(self.output.exists())

    def test_redirect_is_rejected(self):
        with self.assertRaisesRegex(ValueError, "does not follow redirects"):
            self.invoke("--base-url", self.url + "/redirect")
        self.assertEqual(self.requests, ["/redirect/payload"])

    def test_invalid_local_signature_prevents_network(self):
        with self.assertRaises(subprocess.CalledProcessError):
            self.invoke(verifier_error=subprocess.CalledProcessError(1, "signed verifier"))
        self.assertEqual(self.requests, [])

    def test_activation_requires_workflow_evidence_url(self):
        for url in ["", "https://example.invalid/run/123", "https://github.com/test/repo/actions/runs/not-a-number"]:
            with self.subTest(url=url), self.assertRaisesRegex(ValueError, "GitHub Actions"):
                self.invoke("--output", str(self.output), "--proof-url", url)
        self.assertEqual(self.requests, [])

    def test_custom_ca_fixture_cannot_produce_public_activation(self):
        with self.assertRaisesRegex(ValueError, "custom-CA fixture"):
            self.invoke("--output", str(self.output), "--ca-file", str(self.cert), "--proof-url",
                        "https://github.com/sandwichfarm/loopwire/actions/runs/123")
        self.assertFalse(self.output.exists())
        self.assertEqual(self.requests, [])

    def test_https_and_independent_fingerprint_required(self):
        for args in [("--base-url", "http://example.invalid"), ("--base-url", "https://user:pass@example.invalid"),
                     ("--fingerprint", "A" * 8)]:
            with self.subTest(args=args), self.assertRaises(ValueError):
                self.invoke(*args)
        self.assertEqual(self.requests, [])


if __name__ == "__main__":
    unittest.main()
