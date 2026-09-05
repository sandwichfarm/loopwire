#!/usr/bin/env python3
"""Publisher regression tests; real signed fixtures require Debian/Ubuntu tools.

Run: python3 scripts/test-publish-package-repository.py
Add --with-ssh inside a disposable root Docker container with openssh-server to
exercise the real transport. It starts sshd only in that container, uses temporary
host/client keys and known_hosts, and removes them and the server on completion.
No production credentials, services, or audio configuration are used.
"""

import argparse
import base64
import hashlib
import importlib.util
import io
import json
import os
from pathlib import Path
import shutil
import socket
import stat
import subprocess
import sys
import tarfile
import tempfile
import time
import unittest
from unittest import mock


SCRIPT = Path(__file__).with_name("publish-package-repository.py")


def load(name, path):
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


publisher = load("publisher", SCRIPT)
FPR = "A" * 40
WITH_SSH = False


def fixture(root, version="1", revision_date=1, previous=None):
    root.mkdir()
    files = {}
    if previous:
        prior = json.loads((previous / publisher.MANIFEST).read_text())
        for entry in prior["files"]:
            if entry["kind"] == "immutable":
                files[entry["path"]] = (previous / entry["path"]).read_bytes()
    files[f"keys/{FPR}.asc"] = b"synthetic key for filesystem-only tests"
    suites = []
    for suite in publisher.SUITES:
        package = f"pool/{suite}/main/l/loopwire/loopwire_{version}_amd64.deb"
        files[package] = b"package " + version.encode()
        suites.append({"name": suite, "architecture": "amd64", "component": "main", "packages": []})
        for suffix in ("Packages", "Packages.gz"):
            data = f"index {suite} {version} {suffix}".encode()
            prefix = f"dists/{suite}/main/binary-amd64"
            files[f"{prefix}/{suffix}"] = data
            files[f"{prefix}/by-hash/SHA256/{hashlib.sha256(data).hexdigest()}"] = data
        for suffix in ("Release", "InRelease"):
            files[f"dists/{suite}/{suffix}"] = f"{suite} {version} {revision_date} {suffix}".encode()
    entries = []
    for path, data in sorted(files.items()):
        target = root / path
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(data)
        entries.append({"path": path, "kind": publisher.classify(path), "size": len(data),
                        "sha256": hashlib.sha256(data).hexdigest()})
    manifest = {"schemaVersion": 1, "createdAt": revision_date, "validUntil": revision_date + 2592000,
                "signingFingerprint": FPR, "suites": suites, "files": entries}
    write_manifest(root, manifest)
    return json.loads((root / publisher.MANIFEST).read_text())


def write_manifest(root, manifest):
    manifest.pop("revision", None)
    manifest["revision"] = hashlib.sha256(publisher.canonical(manifest)).hexdigest()
    (root / publisher.MANIFEST).write_text(json.dumps(manifest))


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="loopwire-publisher-tests-")
        self.directory = Path(self.temporary.name)
        self.root = self.directory / "origin"
        self.first = self.directory / "first"
        self.second = self.directory / "second"
        self.one = fixture(self.first)
        self.two = fixture(self.second, "2", 2, self.first)

    def tearDown(self):
        self.temporary.cleanup()

    def publish_first(self):
        return publisher.publish_at(self.root, self.first, FPR, "empty")

    def assert_current(self, revision):
        self.assertEqual(publisher.state(self.root, "current"), {"revision": revision})

    def test_publish_idempotence_and_revision_compare_and_swap(self):
        self.assertEqual(self.publish_first()["status"], "published")
        self.assert_current(self.one["revision"])
        self.assertEqual(self.publish_first()["status"], "unchanged")
        with self.assertRaisesRegex(publisher.PublicationError, "compare-and-swap"):
            publisher.publish_at(self.root, self.second, FPR, "empty")
        self.assert_current(self.one["revision"])
        publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        self.assert_current(self.two["revision"])
        self.assertTrue((self.root / "snapshots" / self.one["revision"]).is_dir())

    def test_restrictive_umask_preserves_public_and_private_permissions(self):
        previous_umask = os.umask(0o077)
        try:
            self.publish_first()

            def permissions(path):
                return stat.S_IMODE(path.stat().st_mode)

            self.assertEqual(permissions(self.root), 0o755)
            public = self.root / "public"
            for path in (public, *public.rglob("*")):
                self.assertEqual(permissions(path), 0o755 if path.is_dir() else 0o644, str(path))
            for private in (self.root / "snapshots", self.root / "state"):
                for path in (private, *private.rglob("*")):
                    self.assertEqual(permissions(path), 0o700 if path.is_dir() else 0o600, str(path))
            self.assertEqual(permissions(self.root / ".publish.lock"), 0o600)

            def interrupt(label):
                if label == "journal":
                    raise InterruptedError("inspect durable pending journal permissions")

            with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                with self.assertRaises(InterruptedError):
                    publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
            self.assertEqual(permissions(self.root / "state/pending.json"), 0o600)
        finally:
            os.umask(previous_umask)

    def test_existing_operator_directory_permissions_are_preserved(self):
        self.root.mkdir(mode=0o750)
        (self.root / "public").mkdir(mode=0o750)
        self.root.chmod(0o750)
        (self.root / "public").chmod(0o750)
        self.publish_first()
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o750)
        self.assertEqual(stat.S_IMODE((self.root / "public").stat().st_mode), 0o750)

    def test_old_pool_and_by_hash_survive_without_previous_in_candidate(self):
        self.publish_first()
        independent = self.directory / "independent"
        fixture(independent, "3", 3)
        publisher.publish_at(self.root, independent, FPR, self.one["revision"])
        for entry in self.one["files"]:
            if entry["kind"] == "immutable":
                self.assertEqual(publisher.digest(self.root / "public" / entry["path"]), entry["sha256"])

    def test_immutable_collision_does_not_change_metadata_or_snapshot(self):
        self.publish_first()
        entry = next(item for item in self.two["files"] if item["path"].endswith("loopwire_1_amd64.deb"))
        target = self.second / entry["path"]
        target.write_bytes(b"replaced published package")
        entry.update(size=target.stat().st_size, sha256=publisher.digest(target))
        write_manifest(self.second, self.two)
        with self.assertRaisesRegex(publisher.PublicationError, "immutable URL collision"):
            publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        self.assert_current(self.one["revision"])
        self.assertIsNone(publisher.state(self.root, "pending"))
        self.assertFalse((self.root / "snapshots" / self.two["revision"]).exists())

    def test_order_uploads_every_immutable_before_suite_commit(self):
        self.publish_first()
        events = []

        def check(label):
            events.append(label)
            if label == "immutable":
                for entry in self.two["files"]:
                    if entry["kind"] == "immutable":
                        self.assertEqual(publisher.digest(self.root / "public" / entry["path"]), entry["sha256"])
                for suite in publisher.SUITES:
                    path = f"dists/{suite}/InRelease"
                    self.assertEqual((self.root / "public" / path).read_bytes(), (self.first / path).read_bytes())
            if label == "committed:debian-13":
                path = "dists/ubuntu-24.04/InRelease"
                self.assertEqual((self.root / "public" / path).read_bytes(), (self.first / path).read_bytes())

        with mock.patch.object(publisher, "_checkpoint", side_effect=check):
            publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        self.assertLess(events.index("immutable"), events.index("committed:debian-13"))
        self.assertLess(events.index("committed:debian-13"), events.index("committed:ubuntu-24.04"))

    def test_killed_process_leaves_recoverable_journal_and_blocks_fetch(self):
        self.publish_first()
        code = (
            "import importlib.util,os,sys; from pathlib import Path; "
            "s=importlib.util.spec_from_file_location('publisher',sys.argv[1]); "
            "p=importlib.util.module_from_spec(s); s.loader.exec_module(p); "
            "p._checkpoint=lambda label: os._exit(97) if label=='committed:debian-13' else None; "
            "p.publish_at(Path(sys.argv[2]),Path(sys.argv[3]),sys.argv[4],sys.argv[5])"
        )
        process = subprocess.run([sys.executable, "-c", code, str(SCRIPT), str(self.root),
                                  str(self.second), FPR, self.one["revision"]], check=False)
        self.assertEqual(process.returncode, 97)
        self.assert_current(self.one["revision"])
        self.assertEqual(publisher.state(self.root, "pending")["revision"], self.two["revision"])
        with self.assertRaisesRegex(publisher.PublicationError, "recover"):
            with publisher.selected_snapshot(self.root, FPR):
                pass
        with self.assertRaisesRegex(publisher.PublicationError, "recover"):
            publisher.publish_at(self.root, self.first, FPR, self.one["revision"])
        publisher.recover_at(self.root, FPR, self.two["revision"])
        self.assert_current(self.two["revision"])
        self.assertIsNone(publisher.state(self.root, "pending"))

    def test_every_promotion_checkpoint_is_resumable_with_same_candidate(self):
        checkpoints = ("journal", "immutable", "metadata:debian-13", "committed:debian-13",
                       "metadata:ubuntu-24.04", "committed:ubuntu-24.04", "current")
        for index, checkpoint in enumerate(checkpoints):
            with self.subTest(checkpoint=checkpoint):
                root = self.directory / f"origin-{index}"

                def interrupt(label):
                    if label == checkpoint:
                        raise InterruptedError("simulated process interruption")

                with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                    with self.assertRaises(InterruptedError):
                        publisher.publish_at(root, self.first, FPR, "empty")
                self.assertIsNotNone(publisher.state(root, "pending"))
                publisher.publish_at(root, self.first, FPR, "empty")
                self.assertEqual(publisher.state(root, "current")["revision"], self.one["revision"])
                self.assertIsNone(publisher.state(root, "pending"))

    def test_exclusive_lock_blocks_publish_and_fetch(self):
        self.publish_first()
        with publisher.locked(self.root, create=True):
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                with publisher.selected_snapshot(self.root, FPR):
                    pass

    def test_empty_fetch_has_no_filesystem_side_effects(self):
        with self.assertRaises(publisher.EmptyRepository):
            with publisher.selected_snapshot(self.root, FPR):
                pass
        self.assertFalse(self.root.exists())

    def test_fetch_selects_retained_snapshot(self):
        self.publish_first()
        publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        with publisher.selected_snapshot(self.root, FPR, self.one["revision"]) as (snapshot, manifest):
            self.assertEqual(snapshot.name, self.one["revision"])
            self.assertEqual(manifest, self.one)

    def test_malicious_path_kind_and_revision_fail_before_root_writes(self):
        cases = ("../../escape", "/etc/passwd", "dists/../escape", "state/current.json", "pool//x")
        for index, bad in enumerate(cases):
            with self.subTest(path=bad):
                candidate = self.directory / f"bad-{index}"
                manifest = fixture(candidate)
                manifest["files"][0]["path"] = bad
                write_manifest(candidate, manifest)
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_at(self.root, candidate, FPR, "empty")
                self.assertFalse(self.root.exists())
        self.one["files"][0]["kind"] = "immutable"
        write_manifest(self.first, self.one)
        with self.assertRaisesRegex(publisher.PublicationError, "kind"):
            publisher.publish_at(self.root, self.first, FPR, "empty")

    def test_candidate_symlinks_and_hardlinks_are_rejected(self):
        target = self.first / "unlisted"
        target.symlink_to(self.second / publisher.MANIFEST)
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        target.unlink()
        os.link(self.first / publisher.MANIFEST, target)
        with self.assertRaisesRegex(publisher.PublicationError, "hardlink"):
            self.publish_first()
        self.assertFalse(self.root.exists())

    def test_origin_symlink_and_unmanaged_content_are_rejected(self):
        elsewhere = self.directory / "elsewhere"
        elsewhere.mkdir()
        self.root.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        self.assertEqual(list(elsewhere.iterdir()), [])
        self.root.unlink()
        (self.root / "public").mkdir(parents=True)
        (self.root / "public/existing").write_text("unmanaged")
        with self.assertRaisesRegex(publisher.PublicationError, "unmanaged"):
            self.publish_first()

    def test_public_symlink_and_drift_rejected(self):
        self.publish_first()
        target = self.root / "public" / self.one["files"][0]["path"]
        target.unlink()
        target.symlink_to(self.first / self.one["files"][0]["path"])
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        target.unlink()
        target.write_bytes(b"drift")
        with self.assertRaisesRegex(publisher.PublicationError, "drifted"):
            self.publish_first()

    def test_archive_rejects_traversal_links_and_duplicate_entries(self):
        for kind in ("traversal", "symlink", "hardlink", "duplicate"):
            with self.subTest(kind=kind):
                archive = io.BytesIO()
                with tarfile.open(fileobj=archive, mode="w") as output:
                    member = tarfile.TarInfo("../escape" if kind == "traversal" else publisher.MANIFEST)
                    member.size = 2
                    if kind in ("symlink", "hardlink"):
                        member.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                        member.linkname = "/etc/passwd"
                    output.addfile(member, io.BytesIO(b"{}"))
                    if kind == "duplicate":
                        output.addfile(member, io.BytesIO(b"{}"))
                archive.seek(0)
                destination = self.directory / kind
                destination.mkdir()
                with self.assertRaises(publisher.PublicationError):
                    publisher.read_archive(archive, destination)

    def test_remote_arguments_are_data_and_host_trust_is_mandatory(self):
        args = argparse.Namespace(ssh="publisher@example.invalid", ssh_port=2222, known_hosts=None, identity_file=None)
        request = {"root": "/tmp/path with 'quotes';$(touch /tmp/unsafe)", "action": "fetch"}
        command = publisher.ssh_command(args, request)
        self.assertIn("StrictHostKeyChecking=yes", command)
        self.assertIn("BatchMode=yes", command)
        self.assertIn("ForwardAgent=no", command)
        import shlex
        remote = shlex.split(command[-1])
        self.assertEqual(remote[:2], ["python3", "-c"])
        self.assertEqual(json.loads(base64.urlsafe_b64decode(remote[-1])), request)
        args.ssh = "publisher@host;touch /tmp/unsafe"
        with self.assertRaises(publisher.PublicationError):
            publisher.ssh_command(args, request)


class SignedPublicationTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        # Share the generator suite's real dpkg/OpenSSL/GPG fixture builders.
        cls.fixtures = load("apt_repository_test_fixtures", SCRIPT.with_name("test-apt-repository.py")).RepositoryTests
        cls.fixtures.setUpClass()
        cls.root = cls.fixtures.root
        cls.upgraded = cls.root / "publisher-upgraded"
        cls.fixtures.build(cls.fixtures.release2, "1.1.0", cls.upgraded, "--previous", cls.fixtures.base)
        cls.one = json.loads((cls.fixtures.base / publisher.MANIFEST).read_text())
        cls.two = json.loads((cls.upgraded / publisher.MANIFEST).read_text())

    @classmethod
    def tearDownClass(cls):
        cls.fixtures.tearDownClass()

    def setUp(self):
        self.case_dir = self.root / self.id().split(".")[-1]
        self.case_dir.mkdir()
        self.origin = self.case_dir / "origin"

    def command(self, action, *extra, ok=True):
        command = [sys.executable, str(SCRIPT), action, "--root", str(self.origin),
                   "--public-key", str(self.fixtures.key), "--fingerprint", self.fixtures.fingerprint,
                   *map(str, extra)]
        result = subprocess.run(command, capture_output=True, text=True, check=False)
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def publish(self, *extra, **kwargs):
        return self.command("publish", "--repository", self.fixtures.base, "--expected-revision", "empty", *extra, **kwargs)

    def test_signed_publish_fetch_refresh_and_retained_rollback_input(self):
        self.publish()
        self.command("publish", "--repository", self.upgraded, "--expected-revision", self.one["revision"])
        fetched = self.case_dir / "fetched"
        result = self.command("fetch", "--output", fetched)
        self.assertEqual(json.loads(result.stdout)["revision"], self.two["revision"])
        retained = self.case_dir / "retained"
        result = self.command("fetch", "--revision", self.one["revision"], "--output", retained)
        self.assertEqual(json.loads(result.stdout)["revision"], self.one["revision"])
        self.assertEqual((retained / publisher.MANIFEST).read_bytes(), (self.fixtures.base / publisher.MANIFEST).read_bytes())

    def test_invalid_signature_dry_run_and_empty_fetch_do_not_touch_origin(self):
        self.publish("--dry-run", "--ssh", "unused@example.invalid")
        self.assertFalse(self.origin.exists())
        result = self.command("fetch", "--output", self.case_dir / "empty", ok=False)
        self.assertEqual(result.returncode, 3)
        self.assertEqual(json.loads(result.stdout), {"status": "empty", "revision": None})
        self.assertFalse(self.origin.exists())
        altered = self.case_dir / "altered"
        shutil.copytree(self.fixtures.base, altered)
        manifest = json.loads((altered / publisher.MANIFEST).read_text())
        entry = next(item for item in manifest["files"] if item["path"].endswith("/InRelease"))
        (altered / entry["path"]).write_text("invalid signature")
        entry.update(size=len("invalid signature"), sha256=publisher.digest(altered / entry["path"]))
        write_manifest(altered, manifest)
        result = self.command("publish", "--repository", altered, "--expected-revision", "empty", ok=False)
        self.assertNotEqual(result.returncode, 0)
        self.assertIn("signed repository verification failed", result.stderr)
        self.assertFalse(self.origin.exists())

    def test_recovery_verifies_pending_signed_snapshot(self):
        self.publish()

        def interrupt(label):
            if label == "committed:debian-13":
                raise InterruptedError("simulated interruption")

        with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
            with self.assertRaises(InterruptedError):
                publisher.publish_at(self.origin, self.upgraded, self.fixtures.fingerprint, self.one["revision"])
        self.command("recover", "--dry-run")
        self.assertIsNotNone(publisher.state(self.origin, "pending"))
        self.command("recover")
        self.assertIsNone(publisher.state(self.origin, "pending"))
        self.assertEqual(publisher.state(self.origin, "current")["revision"], self.two["revision"])

    def test_expired_journal_requires_explicit_recovery_then_fresh_signing(self):
        # GnuPG agent sockets must fit the platform's short Unix socket path limit.
        gnupg = self.root / "historical-gnupg"
        gnupg.mkdir(mode=0o700)
        date = int(time.time()) - 3 * 86400

        def run(*command):
            result = subprocess.run(list(map(str, command)), capture_output=True, text=True, check=False)
            self.assertEqual(result.returncode, 0, result.stderr)
            return result.stdout

        try:
            run("gpg", "--homedir", gnupg, "--batch", "--pinentry-mode", "loopback", "--passphrase", "",
                "--faked-system-time", f"{date - 60}!", "--quick-generate-key", "Historical fixture", "rsa2048", "sign", "1y")
            listing = run("gpg", "--homedir", gnupg, "--with-colons", "--list-keys")
            fingerprint = next(line.split(":")[9] for line in listing.splitlines() if line.startswith("fpr:"))
            key = self.case_dir / "historical.asc"
            key.write_text(run("gpg", "--homedir", gnupg, "--armor", "--export", fingerprint))
            candidate = self.case_dir / "expired"
            run(sys.executable, SCRIPT.with_name("apt-repository.py"), "build", "--release-dir", self.fixtures.release1,
                "--version", "1.0.0", "--output", candidate, "--signing-key", fingerprint,
                "--gnupg-home", gnupg, "--date", date, "--valid-for-days", "1",
                "--release-public-key", self.fixtures.release_public)

            def interrupt(label):
                if label == "journal":
                    raise InterruptedError("interrupted before promotion three days ago")

            with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                with self.assertRaises(InterruptedError):
                    publisher.publish_at(self.origin, candidate, fingerprint, "empty")
            options = ["--public-key", key, "--fingerprint", fingerprint]
            rejected = self.command("recover", *options, ok=False)
            self.assertNotEqual(rejected.returncode, 0)
            dry_run = self.command("recover", "--allow-expired", "--dry-run", *options)
            self.assertTrue(json.loads(dry_run.stdout)["requiresRefresh"])
            self.assertIsNotNone(publisher.state(self.origin, "pending"))
            completed = self.command("recover", "--allow-expired", *options)
            self.assertTrue(json.loads(completed.stdout)["requiresRefresh"])
            self.assertIn("APT rejects", json.loads(completed.stdout)["nextAction"])
            self.command("fetch", "--output", self.case_dir / "expired-fetched", *options)
            rejected = self.command("publish", "--repository", candidate, "--expected-revision", "empty", *options, ok=False)
            self.assertNotEqual(rejected.returncode, 0)
        finally:
            subprocess.run(["gpgconf", "--homedir", str(gnupg), "--kill", "gpg-agent"], check=False)

    def test_actual_ssh_publish_fetch_host_trust_and_no_remote_gpg(self):
        if not WITH_SSH:
            self.skipTest("use --with-ssh inside a disposable Docker container")
        self.assertTrue(Path("/.dockerenv").exists() and os.geteuid() == 0,
                        "--with-ssh is restricted to root inside a disposable Docker container")
        sshd = shutil.which("sshd")
        self.assertIsNotNone(sshd, "openssh-server is required for --with-ssh")
        identity = self.case_dir / "identity"
        host_key = self.case_dir / "host-key"
        for key in (identity, host_key):
            subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "", "-f", str(key)], check=True)
        with socket.socket() as listener:
            listener.bind(("127.0.0.1", 0))
            port = listener.getsockname()[1]
        known = self.case_dir / "known_hosts"
        known.write_text(f"[127.0.0.1]:{port} " + host_key.with_suffix(".pub").read_text())
        remote_bin = self.case_dir / "remote-bin"
        remote_bin.mkdir()
        (remote_bin / "python3").symlink_to(sys.executable)
        configuration = self.case_dir / "sshd.conf"
        configuration.write_text(
            f"Port {port}\nListenAddress 127.0.0.1\nHostKey {host_key}\n"
            f"PidFile {self.case_dir / 'sshd.pid'}\nAuthorizedKeysFile {identity}.pub\n"
            "PermitRootLogin prohibit-password\nPasswordAuthentication no\nKbdInteractiveAuthentication no\n"
            f"UsePAM no\nStrictModes no\nAllowUsers root\nLogLevel ERROR\nSetEnv PATH={remote_bin}\n")
        Path("/run/sshd").mkdir(exist_ok=True)
        with (self.case_dir / "sshd.log").open("wb") as log:
            server = subprocess.Popen([sshd, "-D", "-e", "-f", str(configuration)], stdout=log, stderr=log)
            try:
                for _ in range(100):
                    self.assertIsNone(server.poll(), "temporary sshd exited")
                    try:
                        with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                            break
                    except OSError:
                        time.sleep(0.05)
                options = ["--ssh", "root@127.0.0.1", "--ssh-port", str(port),
                           "--identity-file", identity, "--known-hosts", known]
                connection = argparse.Namespace(ssh="root@127.0.0.1", ssh_port=port,
                                                identity_file=identity, known_hosts=known)
                probe = publisher.ssh_command(connection, {})
                probe[-1] = "python3 -c 'import shutil; assert shutil.which(\"gpg\") is None'"
                checked = subprocess.run(probe, capture_output=True, text=True, check=False)
                self.assertEqual(checked.returncode, 0, checked.stderr)
                # The server executes only the transported publisher source; no
                # generator, GPG executable, or private signing key is uploaded.
                self.publish(*options)
                self.assertEqual(json.loads(self.publish(*options).stdout)["status"], "unchanged")
                self.command("fetch", "--output", self.case_dir / "ssh-fetched", *options)
                self.command("publish", "--repository", self.upgraded, "--expected-revision", self.one["revision"], *options)
                result = self.command("publish", "--repository", self.fixtures.base,
                                      "--expected-revision", "empty", *options, ok=False)
                self.assertNotEqual(result.returncode, 0)
                known.write_text("")
                result = self.command("fetch", "--output", self.case_dir / "untrusted", *options, ok=False)
                self.assertNotEqual(result.returncode, 0)
                self.assertFalse((self.case_dir / "untrusted").exists())
            finally:
                server.terminate()
                server.wait(timeout=10)


if __name__ == "__main__":
    if "--with-ssh" in sys.argv:
        WITH_SSH = True
        sys.argv.remove("--with-ssh")
    unittest.main(verbosity=2)
