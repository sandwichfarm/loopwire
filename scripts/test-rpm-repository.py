#!/usr/bin/env python3
"""Credential-free Fedora repository tests with real RPM, GPG, createrepo, and DNF.

Run in the pinned tools image built from packaging/repositories/Dockerfile.rpm-tools.
All keys, packages, repositories, web servers, DNF state, and RPM databases are
temporary. No host repository configuration or production credentials are used.
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


SCRIPT = Path(__file__).with_name("rpm-repository.py")


def run(*args, ok=True, **kwargs):
    result = subprocess.run([str(argument) for argument in args], capture_output=True, text=True, **kwargs)
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
        for tool in (
            "createrepo_c", "dnf", "gpg", "gpgv", "openssl", "rpm", "rpmbuild", "rpmkeys", "rpmsign",
        ):
            if not shutil.which(tool):
                raise RuntimeError(f"{tool} required; run tests in Dockerfile.rpm-tools")
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-rpm-tests-")
        cls.root = Path(cls.temporary.name)
        cls.root.chmod(0o755)
        cls.gnupg = cls.root / "gnupg"
        cls.gnupg.mkdir(mode=0o700)
        cls.fingerprints = []
        for identity in ("Loopwire RPM Test", "Wrong RPM Test"):
            run(
                "gpg", "--homedir", cls.gnupg, "--batch", "--pinentry-mode", "loopback",
                "--passphrase", "", "--quick-generate-key", identity, "rsa2048", "sign", "0",
            )
            listing = run("gpg", "--homedir", cls.gnupg, "--with-colons", "--list-keys", identity).stdout
            cls.fingerprints.append(next(
                line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:")
            ))
        cls.fingerprint, cls.wrong_fingerprint = cls.fingerprints
        cls.key = cls.root / "repository.asc"
        cls.key.write_text(run(
            "gpg", "--homedir", cls.gnupg, "--armor", "--export", cls.fingerprint,
        ).stdout)
        cls.wrong_key = cls.root / "wrong.asc"
        cls.wrong_key.write_text(run(
            "gpg", "--homedir", cls.gnupg, "--armor", "--export", cls.wrong_fingerprint,
        ).stdout)
        cls.release_private = cls.root / "release-private.pem"
        cls.release_public = cls.root / "release-public.pem"
        run(
            "openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
            "-out", cls.release_private,
        )
        run("openssl", "pkey", "-in", cls.release_private, "-pubout", "-out", cls.release_public)
        cls.date = int(time.time())
        cls.release1 = cls.make_release("1.0.0")
        cls.release2 = cls.make_release("1.1.0")
        cls.base = cls.root / "base"
        cls.build(cls.release1, "1.0.0", cls.base)

    @classmethod
    def tearDownClass(cls):
        run("gpgconf", "--homedir", cls.gnupg, "--kill", "gpg-agent", ok=False)
        cls.temporary.cleanup()

    @classmethod
    def make_rpm(
        cls, version, *, name="loopwire", release="1.fc44", architecture="x86_64", suffix="",
    ):
        fixture = cls.root / f"rpm-{version}-{name}-{release}-{architecture}{suffix}"
        top = fixture / "rpmbuild"
        for directory in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
            (top / directory).mkdir(parents=True)
        spec = top / "SPECS/fixture.spec"
        spec.write_text(
            f"Name: {name}\nVersion: {version}\nRelease: {release}\n"
            "Summary: Loopwire repository test fixture\nLicense: MIT\n"
            f"BuildArch: {architecture}\n\n"
            "%description\nRepository fixture.\n\n%prep\n\n%build\n\n"
            "%install\nmkdir -p %{buildroot}/usr/share/loopwire\n"
            f"printf '%s\\n' '{version}{suffix}' > %{{buildroot}}/usr/share/loopwire/fixture\n\n"
            "%files\n/usr/share/loopwire/fixture\n",
        )
        run(
            "rpmbuild", "--define", f"_topdir {top}", "--define", "_buildhost fixture.invalid",
            "--define", f"_source_date_epoch {cls.date}", "--define", "use_source_date_epoch_as_buildtime 1",
            "-bb", spec,
        )
        packages = list((top / "RPMS").glob("**/*.rpm"))
        if len(packages) != 1:
            raise AssertionError(f"expected one RPM fixture, got {packages}")
        return packages[0]

    @classmethod
    def make_release(
        cls, version, *, name="loopwire", release="1.fc44", architecture="x86_64", suffix="",
    ):
        directory = cls.root / f"release-{version}-{name}-{release}-{architecture}{suffix}"
        directory.mkdir()
        built = cls.make_rpm(
            version, name=name, release=release, architecture=architecture, suffix=suffix,
        )
        filename = f"loopwire-{version}-1.fc44.x86_64.rpm"
        shutil.copyfile(built, directory / filename)
        cls.sign_release(directory)
        return directory

    @classmethod
    def sign_release(cls, release):
        packages = sorted(release.glob("*.rpm"))
        (release / "SHA256SUMS").write_text("".join(
            f"{digest(package)}  {package.name}\n" for package in packages
        ))
        run(
            "openssl", "dgst", "-sha256", "-sign", cls.release_private,
            "-out", release / "SHA256SUMS.sig", release / "SHA256SUMS",
        )

    @classmethod
    def build(cls, release, version, output, *extra, ok=True):
        return run(
            sys.executable, SCRIPT, "build", "--release-dir", release, "--version", version,
            "--output", output, "--signing-key", cls.fingerprint, "--gnupg-home", cls.gnupg,
            "--release-public-key", cls.release_public, "--date", cls.date, *extra, ok=ok,
        )

    def setUp(self):
        self.case_dir = self.root / self.id().split(".")[-1]
        self.case_dir.mkdir(mode=0o755)
        self.repo = self.case_dir / "repository"
        shutil.copytree(self.base, self.repo)

    def verify(self, *extra, ok=True, key=None, fingerprint=None):
        return run(
            sys.executable, SCRIPT, "verify", "--repository", self.repo,
            "--public-key", key or self.key, "--fingerprint", fingerprint or self.fingerprint,
            *extra, ok=ok,
        )

    def rewrite_manifest(self, update_packages=False):
        path = self.repo / "repository-manifest.json"
        manifest = json.loads(path.read_text())
        for entry in manifest["files"]:
            file = self.repo / entry["path"]
            if file.is_file():
                entry.update(sha256=digest(file), size=file.stat().st_size)
        if update_packages:
            for package in manifest["packages"]:
                file = self.repo / package["path"]
                package.update(distributedSha256=digest(file), size=file.stat().st_size)
        manifest.pop("revision", None)
        encoded = json.dumps(manifest, sort_keys=True, separators=(",", ":")).encode()
        manifest["revision"] = hashlib.sha256(encoded).hexdigest()
        path.write_text(json.dumps(manifest))

    def dnf_download(self, package="loopwire", *, key_url=None):
        handler = functools.partial(QuietHandler, directory=str(self.repo))
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        state = self.case_dir / f"dnf-{time.time_ns()}"
        repos = state / "repos"
        downloads = state / "downloads"
        for directory in (state, repos, downloads, state / "cache", state / "persist", state / "log"):
            directory.mkdir(exist_ok=True)
        base = f"http://127.0.0.1:{server.server_port}"
        (repos / "loopwire.repo").write_text(
            "[loopwire]\nname=Loopwire test\nenabled=1\n"
            f"baseurl={base}/\ngpgkey={key_url or base + f'/keys/{self.fingerprint}.asc'}\n"
            "gpgcheck=1\nrepo_gpgcheck=1\nmetadata_expire=0\nsslverify=1\n"
        )
        command = [
            "dnf", "--assumeyes", "--setopt", f"reposdir={repos}",
            "--setopt", f"cachedir={state / 'cache'}", "--setopt", f"persistdir={state / 'persist'}",
            "--setopt", f"logdir={state / 'log'}", "--setopt", "optional_metadata_types=",
            "--repo", "loopwire", "download", "--from-repo", "loopwire",
            "--destdir", downloads, package,
        ]
        try:
            return run(*command, ok=False), downloads
        finally:
            server.shutdown()
            server.server_close()
            thread.join()

    def test_signed_chain_and_real_dnf_download(self):
        source = self.release1 / "loopwire-1.0.0-1.fc44.x86_64.rpm"
        source_before = digest(source)
        summary = json.loads(self.verify().stdout)
        self.assertEqual(summary["signingFingerprint"], self.fingerprint)
        self.assertEqual(summary["target"], {
            "distribution": "fedora", "release": "44", "architecture": "x86_64",
        })
        package = summary["packages"][0]
        self.assertEqual(package["sourceReleaseSha256"], source_before)
        self.assertNotEqual(package["distributedSha256"], source_before)
        self.assertEqual(digest(source), source_before, "generator mutated the source release RPM")
        result, downloads = self.dnf_download("loopwire-1.0.0-1.fc44.x86_64")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        downloaded = downloads / "loopwire-1.0.0-1.fc44.x86_64.rpm"
        self.assertEqual(digest(downloaded), package["distributedSha256"])

    def test_retention_version_order_and_fresh_rollback(self):
        upgraded = self.case_dir / "upgraded"
        self.build(self.release2, "1.1.0", upgraded, "--previous", self.base)
        old = json.loads((self.base / "repository-manifest.json").read_text())
        new = json.loads((upgraded / "repository-manifest.json").read_text())
        for entry in old["files"]:
            if entry["kind"] == "immutable":
                self.assertEqual(digest(upgraded / entry["path"]), entry["sha256"])
        self.assertEqual([package["version"] for package in new["packages"]], ["1.0.0", "1.1.0"])
        failed = self.build(
            self.release1, "1.0.0", self.case_dir / "downgrade", "--previous", upgraded, ok=False,
        )
        self.assertNotEqual(failed.returncode, 0)
        rollback = self.case_dir / "rollback"
        run(
            sys.executable, SCRIPT, "rollback", "--repository", self.base, "--output", rollback,
            "--signing-key", self.fingerprint, "--gnupg-home", self.gnupg,
            "--date", self.date + 60,
        )
        rolled = json.loads((rollback / "repository-manifest.json").read_text())
        self.assertEqual(rolled["packages"], old["packages"])
        self.assertEqual(rolled["createdAt"], self.date + 60)
        self.assertNotEqual(rolled["revision"], old["revision"])
        run(
            sys.executable, SCRIPT, "verify", "--repository", rollback,
            "--public-key", self.key, "--fingerprint", self.fingerprint, "--now", self.date + 60,
        )

    def test_release_signature_checksum_and_extra_rpm_rejected(self):
        release = self.case_dir / "release"
        shutil.copytree(self.release1, release)
        (release / "SHA256SUMS.sig").write_bytes(b"invalid")
        self.assertNotEqual(self.build(release, "1.0.0", self.case_dir / "bad", ok=False).returncode, 0)
        self.sign_release(release)
        checksums = release / "SHA256SUMS"
        checksums.write_text(checksums.read_text() * 2)
        run(
            "openssl", "dgst", "-sha256", "-sign", self.release_private,
            "-out", release / "SHA256SUMS.sig", checksums,
        )
        self.assertNotEqual(self.build(
            release, "1.0.0", self.case_dir / "duplicate", ok=False,
        ).returncode, 0)
        self.sign_release(release)
        shutil.copyfile(next(release.glob("*.rpm")), release / "other.rpm")
        self.sign_release(release)
        self.assertNotEqual(self.build(
            release, "1.0.0", self.case_dir / "extra", ok=False,
        ).returncode, 0)
        (release / "other.rpm").unlink()
        shutil.copyfile(next(release.glob("loopwire-1.0.0-1.fc44.x86_64.rpm")),
                        release / "loopwire-1.0.0-1.x86_64.rpm")
        self.sign_release(release)
        self.build(release, "1.0.0", self.case_dir / "known-sibling")

    def test_deterministic_candidate_and_build_metadata_upgrade(self):
        second = self.case_dir / "second"
        self.build(self.release1, "1.0.0", second)
        self.assertEqual(
            (second / "repository-manifest.json").read_bytes(),
            (self.base / "repository-manifest.json").read_bytes(),
        )
        for entry in json.loads((self.base / "repository-manifest.json").read_text())["files"]:
            self.assertEqual(digest(second / entry["path"]), entry["sha256"])
        release = self.make_release("1.0.0+rpmfixture1")
        upgraded = self.case_dir / "upgraded"
        self.build(release, "1.0.0+rpmfixture1", upgraded, "--previous", self.base)
        self.repo = upgraded
        result, downloads = self.dnf_download("loopwire")
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertTrue((downloads / "loopwire-1.0.0+rpmfixture1-1.fc44.x86_64.rpm").is_file())

    def test_encrypted_signing_key_uses_protected_passphrase_file(self):
        home = self.root / "encrypted-gnupg"
        home.mkdir(mode=0o700)
        passphrase = self.case_dir / "passphrase"
        passphrase.write_text("fixture passphrase with spaces\n")
        passphrase.chmod(0o600)
        try:
            run(
                "gpg", "--homedir", home, "--batch", "--pinentry-mode", "loopback",
                "--passphrase-file", passphrase, "--quick-generate-key",
                "Encrypted RPM Fixture", "rsa2048", "sign", "0",
            )
            listing = run("gpg", "--homedir", home, "--with-colons", "--list-keys").stdout
            identity = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
            run("gpgconf", "--homedir", home, "--kill", "gpg-agent")
            output = self.case_dir / "encrypted"
            self.build(
                self.release1, "1.0.0", output, "--gnupg-home", home,
                "--signing-key", identity, "--passphrase-file", passphrase,
                "--date", int(time.time()) + 1,
            )
            run(
                sys.executable, SCRIPT, "verify", "--repository", output,
                "--public-key", output / f"keys/{identity}.asc", "--fingerprint", identity,
            )
            passphrase.chmod(0o644)
            self.assertNotEqual(self.build(
                self.release2, "1.1.0", self.case_dir / "weak-secret",
                "--gnupg-home", home, "--signing-key", identity,
                "--passphrase-file", passphrase, ok=False,
            ).returncode, 0)
        finally:
            run("gpgconf", "--homedir", home, "--kill", "gpg-agent", ok=False)

    def test_package_name_version_architecture_release_and_repack_rejected(self):
        variants = [
            (dict(name="other"), "other"),
            (dict(architecture="noarch"), "architecture"),
            (dict(release="1.fc43"), "release"),
        ]
        for options, suffix in variants:
            release = self.make_release("1.2.0", suffix=suffix, **options)
            self.assertNotEqual(self.build(
                release, "1.2.0", self.case_dir / suffix, ok=False,
            ).returncode, 0)
        self.assertNotEqual(self.build(
            self.release1, "1.0.1", self.case_dir / "version-mismatch", ok=False,
        ).returncode, 0)
        repack = self.make_release("1.0.0", suffix="repack")
        self.assertNotEqual(self.build(
            repack, "1.0.0", self.case_dir / "repack", "--previous", self.base, ok=False,
        ).returncode, 0)

    def test_wrong_repository_signer_rejected_by_verifier_and_dnf(self):
        self.assertNotEqual(self.verify(
            ok=False, fingerprint=self.wrong_fingerprint,
        ).returncode, 0)
        self.assertNotEqual(self.verify(ok=False, key=self.wrong_key).returncode, 0)
        result, _downloads = self.dnf_download(
            key_url=self.wrong_key.resolve().as_uri(),
        )
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_repomd_tampering_and_missing_signature_rejected(self):
        repomd = self.repo / "repodata/repomd.xml"
        repomd.write_text(repomd.read_text().replace("Fedora 44", "Forged 44"))
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        result, _downloads = self.dnf_download()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        (self.repo / "repodata/repomd.xml.asc").unlink()
        result, _downloads = self.dnf_download()
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)

    def test_modified_or_unsigned_rpm_rejected_by_verifier_and_dnf(self):
        package = next(self.repo.glob("packages/*.rpm"))
        package.write_bytes(package.read_bytes() + b"tampered")
        self.rewrite_manifest(update_packages=True)
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        result, _downloads = self.dnf_download("loopwire-1.0.0-1.fc44.x86_64")
        self.assertNotEqual(result.returncode, 0, result.stdout + result.stderr)
        shutil.copytree(self.base, self.repo, dirs_exist_ok=True)
        package = next(self.repo.glob("packages/*.rpm"))
        run("rpmsign", "--delsign", package)
        self.rewrite_manifest(update_packages=True)
        self.assertNotEqual(self.verify(ok=False).returncode, 0)

    def test_tampered_or_incomplete_metadata_and_previous_snapshot_rejected(self):
        primary = next(self.repo.glob("repodata/*-primary.xml.gz"))
        primary.write_bytes(primary.read_bytes() + b"tampered")
        self.rewrite_manifest()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        self.assertNotEqual(self.build(
            self.release2, "1.1.0", self.case_dir / "invalid-previous",
            "--previous", self.repo, ok=False,
        ).returncode, 0)
        shutil.copytree(self.base, self.repo, dirs_exist_ok=True)
        next(self.repo.glob("repodata/*-filelists.xml.gz")).unlink()
        self.assertNotEqual(self.verify(ok=False).returncode, 0)

    def test_expired_future_and_forged_validity_rejected(self):
        self.assertNotEqual(self.verify("--now", self.date + 31 * 86400, ok=False).returncode, 0)
        self.assertNotEqual(self.verify("--now", self.date - 60, ok=False).returncode, 0)
        manifest = json.loads((self.repo / "repository-manifest.json").read_text())
        manifest["validUntil"] += 365 * 86400
        manifest.pop("revision")
        manifest["revision"] = hashlib.sha256(json.dumps(
            manifest, sort_keys=True, separators=(",", ":"),
        ).encode()).hexdigest()
        (self.repo / "repository-manifest.json").write_text(json.dumps(manifest))
        self.assertNotEqual(self.verify("--now", self.date + 31 * 86400, ok=False).returncode, 0)

    def test_path_classification_extra_file_and_manifest_duplicates_rejected(self):
        path = self.repo / "repository-manifest.json"
        original = path.read_text()
        for replacement in ("../../outside", "/absolute", "repodata/../secret", "packages//double"):
            manifest = json.loads(original)
            manifest["files"][0]["path"] = replacement
            path.write_text(json.dumps(manifest))
            self.assertNotEqual(self.verify(ok=False).returncode, 0)
        path.write_text(original)
        manifest = json.loads(original)
        manifest["files"][0]["kind"] = "metadata"
        manifest.pop("revision")
        manifest["revision"] = hashlib.sha256(json.dumps(
            manifest, sort_keys=True, separators=(",", ":"),
        ).encode()).hexdigest()
        path.write_text(json.dumps(manifest))
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        path.write_text(original)
        (self.repo / "unadvertised").write_text("extra")
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        (self.repo / "unadvertised").unlink()
        path.write_text(original.replace(
            '"schema": "loopwire.rpm-repository.v1",',
            '"schema": "duplicate",\n  "schema": "loopwire.rpm-repository.v1",',
        ))
        self.assertNotEqual(self.verify(ok=False).returncode, 0)

    def test_symlink_hardlink_and_output_reuse_rejected(self):
        package = next(self.repo.glob("packages/*.rpm"))
        original = package.read_bytes()
        package.unlink()
        package.symlink_to(self.base / package.relative_to(self.repo))
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        package.unlink()
        package.write_bytes(original)
        os.link(package, self.case_dir / "hardlink")
        self.assertNotEqual(self.verify(ok=False).returncode, 0)
        output = self.case_dir / "exists"
        output.mkdir()
        self.assertNotEqual(self.build(
            self.release2, "1.1.0", output, ok=False,
        ).returncode, 0)


if __name__ == "__main__":
    unittest.main(verbosity=2)
