#!/usr/bin/env python3
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

SCRIPT = Path(__file__).with_name("publish-apt-workflow.sh").resolve()


class PreflightTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory(prefix="loopwire-apt-preflight-")
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        binary = self.root / "bin"
        binary.mkdir()
        gpg = binary / "gpg"
        gpg.write_text('#!/bin/sh\nprintf called > "$APT_TEST_MARKER"\nexit 1\n')
        gpg.chmod(0o755)
        self.marker = self.root / "used-key"
        self.env = {
            **os.environ, "PATH": f"{binary}:{os.environ['PATH']}", "APT_TEST_MARKER": str(self.marker),
            "APT_REPOSITORY_URL": "https://packages.example.invalid/apt",
            "APT_REPOSITORY_HOST": "publisher@example.invalid", "APT_REPOSITORY_ROOT": "/srv/loopwire",
            "APT_SIGNING_FINGERPRINT": "A" * 40, "APT_SSH_PRIVATE_KEY": "private-ssh-fixture",
            "APT_SSH_KNOWN_HOSTS": "known-hosts-fixture", "APT_SIGNING_KEY": "private-gpg-fixture",
            "RUNNER_TEMP": str(self.root), "GITHUB_REPOSITORY": "sandwichfarm/loopwire",
            "GITHUB_SERVER_URL": "https://github.com", "GITHUB_RUN_ID": "123",
            "OPERATION": "publish", "RELEASE_TAG": "v1.2.3",
        }

    def rejected(self, values, message):
        result = subprocess.run(["bash", str(SCRIPT)], env={**self.env, **values}, capture_output=True, text=True)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn(message, result.stderr)
        self.assertFalse(self.marker.exists(), "invalid input reached signing-key operations")
        self.assertNotIn("private-ssh-fixture", result.stdout + result.stderr)
        self.assertNotIn("private-gpg-fixture", result.stdout + result.stderr)

    def test_https_url_rejected_before_keys_or_origin_access(self):
        for url in ["http://example.invalid", "https://user:pass@example.invalid", "https://example.invalid/?",
                    "https://example.invalid/#", "https://example.invalid/\ninjected"]:
            with self.subTest(url=url):
                self.rejected({"APT_REPOSITORY_URL": url}, "base URL")

    def test_missing_configuration(self):
        self.rejected({"APT_SIGNING_KEY": ""}, "missing configuration: APT_SIGNING_KEY")

    def test_tag_is_validated(self):
        self.rejected({"RELEASE_TAG": "v1.2.3; echo unexpected"}, "stable vX.Y.Z")

    def test_rollback_revision_is_validated(self):
        self.rejected({"OPERATION": "rollback", "ROLLBACK_REVISION": "HEAD"}, "revision SHA-256")

    def test_fingerprint_is_validated(self):
        self.rejected({"APT_SIGNING_FINGERPRINT": "short"}, "fingerprint")


if __name__ == "__main__":
    unittest.main()
