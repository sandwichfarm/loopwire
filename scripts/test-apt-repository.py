#!/usr/bin/env python3
"""Credential-free APT repository regression tests using real dpkg, GPG and APT.

Run on Ubuntu 24.04 or Debian 13 with python3, dpkg-dev, apt-utils, gnupg,
and openssl installed. All keys, package fixtures, servers and APT state are
temporary; the host's sources, trusted keyrings and package database are unused.
"""

import functools
import hashlib
import http.server
import json
import os
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import threading
import time
import unittest


SCRIPT = Path(__file__).with_name("apt-repository.py")
SUITES = {"ubuntu-24.04": "ubuntu24.04", "debian-13": "debian13"}


def run(*args, ok=True, **kwargs):
    result = subprocess.run([str(arg) for arg in args], capture_output=True, text=True, **kwargs)
    if ok and result.returncode:
        raise AssertionError(f"{args!r}\n{result.stdout}\n{result.stderr}")
    return result


def digest(path):
    return hashlib.sha256(path.read_bytes()).hexdigest()


class QuietHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


class RepositoryTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        for tool in ("dpkg-deb", "dpkg", "gpg", "gpgv", "apt-get", "openssl"):
            if not shutil.which(tool):
                raise RuntimeError(f"{tool} required; run these tests in an Ubuntu/Debian container")
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-apt-tests-")
        cls.root = Path(cls.temporary.name)
        cls.root.chmod(0o755)
        cls.gnupg = cls.root / "gnupg"
        cls.gnupg.mkdir(mode=0o700)
        cls.fingerprints = []
        for identity in ("Loopwire Test", "Wrong Test"):
            run("gpg", "--homedir", cls.gnupg, "--batch", "--pinentry-mode", "loopback",
                "--passphrase", "", "--quick-generate-key", identity, "rsa2048", "sign", "1d")
            listing = run("gpg", "--homedir", cls.gnupg, "--with-colons", "--list-keys", identity).stdout
            cls.fingerprints.append(next(line.split(":")[9] for line in listing.splitlines()
                                         if line.startswith("fpr:")))
        cls.fingerprint, cls.wrong_fingerprint = cls.fingerprints
        cls.key = cls.root / "archive.asc"
        cls.key.write_text(run("gpg", "--homedir", cls.gnupg, "--armor", "--export",
                               cls.fingerprint).stdout)
        cls.release_private = cls.root / "release-private.pem"
        cls.release_public = cls.root / "release-public.pem"
        run("openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
            "-out", cls.release_private)
        run("openssl", "pkey", "-in", cls.release_private, "-pubout", "-out", cls.release_public)
        cls.release1 = cls.make_release("1.0.0")
        cls.release2 = cls.make_release("1.1.0")
        cls.date = int(time.time())
        cls.base = cls.root / "base"
        cls.build(cls.release1, "1.0.0", cls.base)

    @classmethod
    def tearDownClass(cls):
        run("gpgconf", "--homedir", cls.gnupg, "--kill", "gpg-agent", ok=False)
        cls.temporary.cleanup()

    @classmethod
    def make_release(cls, version, architecture="amd64", package_name="loopwire", suffix=""):
        release = cls.root / f"release-{version}-{architecture}-{package_name}{suffix}"
        release.mkdir()
        for suite, revision in SUITES.items():
            package_root = cls.root / f"pkg-{version}-{suite}-{architecture}-{package_name}{suffix}"
            (package_root / "DEBIAN").mkdir(parents=True)
            (package_root / "usr/share/loopwire").mkdir(parents=True)
            (package_root / "usr/share/loopwire/fixture").write_text(version + suffix)
            (package_root / "DEBIAN/control").write_text(
                f"Package: {package_name}\nVersion: {version}-1{revision}\n"
                f"Architecture: {architecture}\nMaintainer: Test <test@example.invalid>\n"
                "Description: Loopwire repository fixture\n A multiline description.\n")
            output = release / f"loopwire_{version}-1{revision}_amd64.deb"
            run("dpkg-deb", "--root-owner-group", "--build", package_root, output)
        cls.sign_release(release)
        return release

    @classmethod
    def sign_release(cls, release):
        (release / "SHA256SUMS").write_text("".join(
            f"{digest(path)}  {path.name}\n" for path in sorted(release.glob("*.deb"))))
        run("openssl", "dgst", "-sha256", "-sign", cls.release_private,
            "-out", release / "SHA256SUMS.sig", release / "SHA256SUMS")

    @classmethod
    def build(cls, release, version, output, *extra, ok=True):
        return run(sys.executable, SCRIPT, "build", "--release-dir", release, "--version", version,
                   "--output", output, "--signing-key", cls.fingerprint, "--gnupg-home", cls.gnupg,
                   "--release-public-key", cls.release_public, "--date", cls.date, *extra, ok=ok)

    def setUp(self):
        self.case_dir = self.root / self.id().split(".")[-1]
        self.case_dir.mkdir(mode=0o755)
        self.repo = self.case_dir / "repository"
        shutil.copytree(self.base, self.repo)

    def verify(self, *extra, ok=True):
        return run(sys.executable, SCRIPT, "verify", "--repository", self.repo,
                   "--public-key", self.key, "--fingerprint", self.fingerprint, *extra, ok=ok)

    def rewrite_manifest(self):
        manifest_path = self.repo / "repository-manifest.json"
        manifest = json.loads(manifest_path.read_text())
        for entry in manifest["files"]:
            path = self.repo / entry["path"]
            if path.is_file():
                entry.update(sha256=digest(path), size=path.stat().st_size)
        manifest.pop("revision", None)
        encoded = json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()
        manifest["revision"] = hashlib.sha256(encoded).hexdigest()
        manifest_path.write_text(json.dumps(manifest))

    def apt(self, suite="ubuntu-24.04", operation=("update",), key=None):
        handler = functools.partial(QuietHandler, directory=str(self.repo))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        state = self.case_dir / "apt"
        state.mkdir(exist_ok=True)
        state.chmod(0o755)
        for directory in ("lists", "cache", "downloads"):
            (state / directory).mkdir(exist_ok=True)
            (state / directory).chmod(0o777)
        source = state / "loopwire.sources"
        source.write_text(
            f"Types: deb\nURIs: http://127.0.0.1:{server.server_port}\nSuites: {suite}\n"
            f"Components: main\nArchitectures: amd64\nSigned-By: {key or self.key}\nBy-Hash: force\n")
        args = ["apt-get", "-o", f"Dir::Etc::sourcelist={source}", "-o", "Dir::Etc::sourceparts=-",
                "-o", f"Dir::State::lists={state / 'lists'}", "-o", f"Dir::Cache={state / 'cache'}",
                "-o", "Dir::State::status=/dev/null", "-o", "APT::Architecture=amd64",
                "-o", "APT::Architectures::=amd64", "-o", "Acquire::Languages=none",
                "-o", "APT::Update::Error-Mode=any"]
        try:
            update = run(*args, "update", ok=False, cwd=state / "downloads")
            if operation == ("update",) or update.returncode:
                return update
            return run(*args, *operation, ok=False, cwd=state / "downloads")
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_signed_chain_and_real_apt_download_both_suites(self):
        summary = json.loads(self.verify().stdout)
        self.assertEqual(summary["signingFingerprint"], self.fingerprint)
        for suite, revision in SUITES.items():
            result = self.apt(suite, ("download", f"loopwire=1.0.0-1{revision}"))
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
            downloaded = self.case_dir / "apt/downloads" / f"loopwire_1.0.0-1{revision}_amd64.deb"
            self.assertEqual(digest(downloaded), digest(self.release1 / downloaded.name))

    def test_retention_version_order_and_fresh_rollback(self):
        upgraded = self.case_dir / "upgraded"
        self.build(self.release2, "1.1.0", upgraded, "--previous", self.base)
        old = json.loads((self.base / "repository-manifest.json").read_text())
        new = json.loads((upgraded / "repository-manifest.json").read_text())
        for entry in old["files"]:
            if entry["kind"] == "immutable":
                self.assertEqual(digest(upgraded / entry["path"]), entry["sha256"])
        for suite in new["suites"]:
            self.assertEqual(len(suite["packages"]), 2)
        failed = self.build(self.release1, "1.0.0", self.case_dir / "downgrade",
                            "--previous", upgraded, ok=False)
        self.assertNotEqual(failed.returncode, 0)
        rollback = self.case_dir / "rollback"
        run(sys.executable, SCRIPT, "rollback", "--repository", self.base, "--output", rollback,
            "--signing-key", self.fingerprint, "--gnupg-home", self.gnupg,
            "--date", self.date + 60)
        rolled = json.loads((rollback / "repository-manifest.json").read_text())
        self.assertEqual(rolled["suites"], old["suites"])
        self.assertGreater(rolled["createdAt"], old["createdAt"])
        self.assertNotEqual(rolled["revision"], old["revision"])
        run(sys.executable, SCRIPT, "verify", "--repository", rollback, "--public-key", self.key,
            "--fingerprint", self.fingerprint, "--now", self.date + 60)

    def test_release_input_signature_and_duplicate_checksum_rejected(self):
        release = self.case_dir / "release"
        shutil.copytree(self.release1, release)
        (release / "SHA256SUMS.sig").write_bytes(b"invalid")
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "bad", ok=False).returncode, 0)
        self.sign_release(release)
        checksums = release / "SHA256SUMS"
        checksums.write_text(checksums.read_text() * 2)
        run("openssl", "dgst", "-sha256", "-sign", self.release_private,
            "-out", release / "SHA256SUMS.sig", checksums)
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "duplicate", ok=False).returncode, 0)
        self.sign_release(release)
        shutil.copyfile(next(release.glob("*.deb")), release / "duplicate.deb")
        self.sign_release(release)
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "extra-deb", ok=False).returncode, 0)

    def test_reproducible_signed_candidate_and_build_metadata_upgrade(self):
        second = self.case_dir / "second"
        self.build(self.release1, "1.0.0", second)
        self.assertEqual((second / "repository-manifest.json").read_bytes(),
                         (self.base / "repository-manifest.json").read_bytes())
        release = self.make_release("1.0.0+aptfixture1")
        upgraded = self.case_dir / "upgraded"
        self.build(release, "1.0.0+aptfixture1", upgraded, "--previous", self.base)
        self.repo = upgraded
        result = self.apt(operation=("download", "loopwire"))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((self.case_dir / "apt/downloads/loopwire_1.0.0+aptfixture1-1ubuntu24.04_amd64.deb").is_file())

    def test_encrypted_signing_key_uses_passphrase_file(self):
        # GnuPG's Unix socket pathname must fit the platform's short limit.
        home = self.root / "encrypted-gnupg"
        home.mkdir(mode=0o700)
        passphrase = self.case_dir / "passphrase"
        passphrase.write_text("fixture passphrase with spaces\n")
        passphrase.chmod(0o600)
        try:
            run("gpg", "--homedir", home, "--batch", "--pinentry-mode", "loopback", "--passphrase-file",
                passphrase, "--quick-generate-key", "Encrypted Fixture", "rsa2048", "sign", "1d")
            listing = run("gpg", "--homedir", home, "--with-colons", "--list-keys").stdout
            identity = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
            run("gpgconf", "--homedir", home, "--kill", "gpg-agent")
            output = self.case_dir / "encrypted"
            self.build(self.release1, "1.0.0", output, "--gnupg-home", home, "--signing-key", identity,
                       "--passphrase-file", passphrase, "--date", int(time.time()))
            run(sys.executable, SCRIPT, "verify", "--repository", output, "--fingerprint", identity,
                "--public-key", output / f"keys/{identity}.asc")
        finally:
            run("gpgconf", "--homedir", home, "--kill", "gpg-agent", ok=False)

    def test_package_architecture_name_and_version_rejected(self):
        for architecture, name in (("arm64", "loopwire"), ("amd64", "other")):
            release = self.make_release("1.2.0", architecture, name)
            self.assertNotEqual(self.build(release, "1.2.0", self.case_dir / name / architecture,
                                          ok=False).returncode, 0)
        self.assertNotEqual(self.build(self.release1, "1.0.0-rc.1", self.case_dir / "prerelease",
                                      ok=False).returncode, 0)
        release = self.case_dir / "mismatched-suite"
        shutil.copytree(self.release1, release)
        ubuntu = release / "loopwire_1.0.0-1ubuntu24.04_amd64.deb"
        debian = release / "loopwire_1.0.0-1debian13_amd64.deb"
        shutil.copyfile(ubuntu, debian)
        self.sign_release(release)
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "bad-suite", ok=False).returncode, 0)

    def test_wrong_signer_rejected(self):
        self.assertNotEqual(self.verify("--fingerprint", self.wrong_fingerprint, ok=False).returncode, 0)
        wrong_key = self.case_dir / "wrong.asc"
        wrong_key.write_text(run("gpg", "--homedir", self.gnupg, "--armor", "--export",
                                 self.wrong_fingerprint).stdout)
        self.assertNotEqual(self.apt(key=wrong_key).returncode, 0)

    def test_signed_metadata_tampering_and_unsigned_repository_rejected(self):
        inrelease = self.repo / "dists/ubuntu-24.04/InRelease"
        inrelease.write_text(inrelease.read_text().replace("Origin: Loopwire", "Origin: Forged!!"))
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        self.assertNotEqual(self.apt().returncode, 0)
        inrelease.unlink()
        self.assertNotEqual(self.apt().returncode, 0)

    def test_modified_package_rejected_by_verifier_and_apt(self):
        package = next(self.repo.glob("pool/ubuntu-24.04/**/*.deb"))
        package.write_bytes(package.read_bytes() + b"tampered")
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        result = self.apt(operation=("download", "loopwire=1.0.0-1ubuntu24.04"))
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_tampered_index_and_previous_snapshot_rejected(self):
        index = self.repo / "dists/ubuntu-24.04/main/binary-amd64/Packages"
        index.write_text(index.read_text().replace("Version: 1.0.0", "Version: 9.0.0"))
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        self.assertNotEqual(self.build(self.release2, "1.1.0", self.case_dir / "from-invalid",
                                      "--previous", self.repo, ok=False).returncode, 0)

    def test_expired_and_future_metadata_rejected(self):
        self.assertNotEqual(self.verify("--now", self.date + 31 * 86400, ok=False).returncode, 0)
        self.assertNotEqual(self.verify("--now", self.date - 60, ok=False).returncode, 0)

    def test_path_manifest_classification_and_extras_rejected(self):
        path = self.repo / "repository-manifest.json"
        original = path.read_text()
        for replacement in ("../../outside", "/absolute", "dists/../secret", "pool//double"):
            manifest = json.loads(original)
            manifest["files"][0]["path"] = replacement
            path.write_text(json.dumps(manifest))
            self.assertNotEqual(self.verify(ok=False).returncode, 0)
        path.write_text(original)
        manifest = json.loads(original)
        manifest["files"][0]["kind"] = "metadata" if manifest["files"][0]["kind"] == "immutable" else "immutable"
        path.write_text(json.dumps(manifest))
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        path.write_text(original)
        (self.repo / "unadvertised").write_text("extra")
        self.assertNotEqual(self.verify(ok=False).returncode, 0)

    def test_symlink_hardlink_and_same_version_repack_rejected(self):
        package = next(self.repo.glob("pool/**/*.deb"))
        original = package.read_bytes()
        package.unlink()
        package.symlink_to(self.release1 / package.name)
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        package.unlink()
        package.write_bytes(original)
        os.link(package, self.case_dir / "hardlink")
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        release = self.make_release("1.0.0", suffix="repack")
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "repack",
                                      "--previous", self.base, ok=False).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
