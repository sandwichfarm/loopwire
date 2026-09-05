#!/usr/bin/env python3
"""Regression tests for the Fedora RPM repository publisher.

Run locally with Python's standard library:
  python3 scripts/test-publish-rpm-repository.py

Pass --with-ssh inside the pinned RPM tools container to start a disposable
loopback-only sshd and exercise publish/fetch/recover with generated client and
host keys. No production host, credentials, keyring, or repository is touched.
"""

import argparse
import base64
import fcntl
import functools
import hashlib
import http.server
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
import threading
import time
import unittest
import urllib.error
import urllib.request
from unittest import mock


SCRIPT = Path(__file__).with_name("publish-rpm-repository.py")
WITH_SSH = False
FPR = "A" * 40
SUSE = "opensuse-tumbleweed-x86_64"


def load(name, path):
    specification = importlib.util.spec_from_file_location(name, path)
    module = importlib.util.module_from_spec(specification)
    specification.loader.exec_module(module)
    return module


publisher = load("rpm_publisher", SCRIPT)


class QuietHttpHandler(http.server.SimpleHTTPRequestHandler):
    def log_message(self, *_args):
        pass


def write_manifest(root, manifest):
    manifest.pop("revision", None)
    manifest["revision"] = hashlib.sha256(publisher.canonical(manifest)).hexdigest()
    (root / publisher.MANIFEST).write_text(json.dumps(manifest), encoding="utf-8")
    return manifest


def fixture(root, version="1.0.0", created=1, package_bytes=None,
            target=publisher.DEFAULT_TARGET):
    target, config, _package_path = publisher.target_config(target)
    root.mkdir()
    package = f"packages/loopwire-{version}-{config['packageRelease']}.x86_64.rpm"
    files = {
        package: package_bytes or f"rpm package {version}".encode(),
        f"keys/{FPR}.asc": b"synthetic public key",
        "repodata/repomd.xml": f"repomd {version} {created}".encode(),
        "repodata/repomd.xml.asc": f"signature {version} {created}".encode(),
    }
    for kind in ("primary", "filelists", "other"):
        data = f"{kind} {version} {created}".encode()
        files[f"repodata/{hashlib.sha256(data).hexdigest()}-{kind}.xml.gz"] = data
    entries = []
    for path, data in sorted(files.items()):
        candidate_file = root / path
        candidate_file.parent.mkdir(parents=True, exist_ok=True)
        candidate_file.write_bytes(data)
        entries.append({
            "path": path,
            "kind": publisher.classify(path, target),
            "size": len(data),
            "sha256": hashlib.sha256(data).hexdigest(),
        })
    package_data = files[package]
    package_record = {
        "name": "loopwire",
        "version": version,
        "release": config["packageRelease"],
        "architecture": "x86_64",
        "path": package,
        "sourceReleaseSha256": "1" * 64,
        "distributedSha256": hashlib.sha256(package_data).hexdigest(),
        "size": len(package_data),
    }
    if config["sourceRevision"]:
        package_record["sourceRevision"] = "2" * 40
    manifest = {
        "schema": publisher.SCHEMA,
        "schemaVersion": 1,
        "createdAt": created,
        "validUntil": created + 2592000,
        "signingFingerprint": FPR,
        "target": config["manifest"].copy(),
        "packages": [package_record],
        "files": entries,
    }
    return json.loads(json.dumps(write_manifest(root, manifest)))


class PublicationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="loopwire-rpm-publisher-tests-")
        self.directory = Path(self.temporary.name)
        self.root = self.directory / "origin"
        self.first = self.directory / "first"
        self.second = self.directory / "second"
        self.one = fixture(self.first)
        self.two = fixture(self.second, "1.1.0", 2)

    def tearDown(self):
        self.temporary.cleanup()

    @property
    def channel(self):
        return publisher.public_channel(self.root)

    def publish_first(self):
        return publisher.publish_at(self.root, self.first, FPR, "empty")

    def assert_current(self, revision):
        self.assertEqual(publisher.state(self.root, "current"), {"revision": revision})

    def test_publish_idempotence_cas_retention_and_fetch(self):
        self.assertEqual(self.publish_first()["status"], "published")
        self.assertEqual(self.publish_first()["status"], "unchanged")
        with self.assertRaisesRegex(publisher.PublicationError, "compare-and-swap"):
            publisher.publish_at(self.root, self.second, FPR, "empty")
        publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        self.assert_current(self.two["revision"])
        old_package = self.one["packages"][0]["path"]
        self.assertEqual((self.channel / old_package).read_bytes(),
                         (self.first / old_package).read_bytes())
        self.assertTrue((self.root / "snapshots" / self.one["revision"]).is_dir())
        with publisher.selected_snapshot(self.root, FPR, self.one["revision"]) as (snapshot, manifest):
            self.assertEqual(snapshot.name, self.one["revision"])
            self.assertEqual(manifest, self.one)

    def test_restrictive_umask_sets_public_and_private_permissions(self):
        previous_umask = os.umask(0o077)
        try:
            self.publish_first()

            def permissions(path):
                return stat.S_IMODE(path.stat().st_mode)

            self.assertEqual(permissions(self.root), 0o755)
            public = self.root / "public"
            for path in (public, *public.rglob("*")):
                self.assertEqual(permissions(path), 0o755 if path.is_dir() else 0o644,
                                 str(path))
            for private in (self.root / "snapshots", self.root / "state"):
                for path in (private, *private.rglob("*")):
                    self.assertEqual(permissions(path), 0o700 if path.is_dir() else 0o600,
                                     str(path))
            self.assertEqual(permissions(self.root / ".publish.lock"), 0o600)
        finally:
            os.umask(previous_umask)

    def test_existing_operator_root_permissions_are_preserved(self):
        self.root.mkdir(mode=0o750)
        (self.root / "public").mkdir(mode=0o750)
        self.root.chmod(0o750)
        (self.root / "public").chmod(0o750)
        self.publish_first()
        self.assertEqual(stat.S_IMODE(self.root.stat().st_mode), 0o750)
        self.assertEqual(stat.S_IMODE((self.root / "public").stat().st_mode), 0o750)

    def test_immutable_collision_fails_before_journal_or_snapshot(self):
        self.publish_first()
        collision = self.directory / "collision"
        changed = fixture(collision, "1.0.0", 3, b"different bytes at immutable URL")
        with self.assertRaisesRegex(publisher.PublicationError, "immutable URL collision"):
            publisher.publish_at(self.root, collision, FPR, self.one["revision"])
        self.assert_current(self.one["revision"])
        self.assertIsNone(publisher.state(self.root, "pending"))
        self.assertFalse((self.root / "snapshots" / changed["revision"]).exists())

    def test_commit_order_is_signature_then_atomic_repomd(self):
        self.publish_first()
        events = []

        def inspect(label):
            events.append(label)
            public_xml = (self.channel / "repodata/repomd.xml").read_bytes()
            public_signature = (self.channel / "repodata/repomd.xml.asc").read_bytes()
            if label == "immutable":
                self.assertEqual(public_xml, (self.first / "repodata/repomd.xml").read_bytes())
                self.assertEqual(public_signature,
                                 (self.first / "repodata/repomd.xml.asc").read_bytes())
            elif label == "signature":
                self.assertEqual(public_xml, (self.first / "repodata/repomd.xml").read_bytes())
                self.assertEqual(public_signature,
                                 (self.second / "repodata/repomd.xml.asc").read_bytes())
            elif label == "committed":
                self.assertEqual(public_xml, (self.second / "repodata/repomd.xml").read_bytes())
                self.assertEqual(public_signature,
                                 (self.second / "repodata/repomd.xml.asc").read_bytes())

        with mock.patch.object(publisher, "_checkpoint", side_effect=inspect):
            publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
        self.assertLess(events.index("immutable"), events.index("signature"))
        self.assertLess(events.index("signature"), events.index("committed"))

    def test_every_promotion_checkpoint_is_recoverable(self):
        for index, checkpoint in enumerate(
                ("journal", "immutable", "signature", "committed", "manifest", "current")):
            with self.subTest(checkpoint=checkpoint):
                root = self.directory / f"checkpoint-{index}"

                def interrupt(label):
                    if label == checkpoint:
                        raise InterruptedError("simulated interruption")

                with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                    with self.assertRaises(InterruptedError):
                        publisher.publish_at(root, self.first, FPR, "empty")
                self.assertEqual(publisher.state(root, "pending")["revision"],
                                 self.one["revision"])
                publisher.recover_at(root, FPR, self.one["revision"])
                self.assertEqual(publisher.state(root, "current")["revision"],
                                 self.one["revision"])
                self.assertIsNone(publisher.state(root, "pending"))

    def test_killed_process_leaves_durable_journal_and_blocks_competitors(self):
        self.publish_first()
        code = (
            "import importlib.util,os,sys; from pathlib import Path; "
            "s=importlib.util.spec_from_file_location('p',sys.argv[1]); "
            "p=importlib.util.module_from_spec(s); s.loader.exec_module(p); "
            "p._checkpoint=lambda label: os._exit(97) if label=='signature' else None; "
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

    def test_exclusive_flock_blocks_publish_fetch_and_recovery(self):
        self.publish_first()
        descriptor = os.open(self.root / ".publish.lock", os.O_RDONLY | os.O_NOFOLLOW)
        fcntl.flock(descriptor, fcntl.LOCK_EX | fcntl.LOCK_NB)
        try:
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                with publisher.selected_snapshot(self.root, FPR):
                    pass
        finally:
            os.close(descriptor)

    def test_separate_process_lock_blocks_concurrent_cas_writer(self):
        self.publish_first()
        code = (
            "import fcntl,os,sys; "
            "fd=os.open(sys.argv[1],os.O_RDONLY|os.O_NOFOLLOW); "
            "fcntl.flock(fd,fcntl.LOCK_EX); print('locked',flush=True); "
            "sys.stdin.readline(); os.close(fd)"
        )
        holder = subprocess.Popen(
            [sys.executable, "-c", code, str(self.root / ".publish.lock")],
            stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True,
        )
        try:
            self.assertEqual(holder.stdout.readline().strip(), "locked")
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                publisher.publish_at(self.root, self.second, FPR, self.one["revision"])
            self.assert_current(self.one["revision"])
        finally:
            holder.stdin.write("release\n")
            holder.stdin.flush()
            holder.wait(timeout=10)
            holder.stdin.close()
            holder.stdout.close()

    def test_empty_fetch_has_no_filesystem_side_effect(self):
        with self.assertRaises(publisher.EmptyRepository):
            with publisher.selected_snapshot(self.root, FPR):
                pass
        self.assertFalse(self.root.exists())

    def test_malicious_paths_kind_target_and_revision_fail_before_write(self):
        for index, bad in enumerate(("../../escape", "/etc/passwd", "repodata/../escape",
                                     "state/current.json", "packages//x.rpm")):
            with self.subTest(path=bad):
                candidate = self.directory / f"bad-path-{index}"
                manifest = fixture(candidate, f"2.0.{index}")
                manifest["files"][0]["path"] = bad
                write_manifest(candidate, manifest)
                with self.assertRaises(publisher.PublicationError):
                    publisher.publish_at(self.root, candidate, FPR, "empty")
                self.assertFalse(self.root.exists())
        self.one["target"]["release"] = "45"
        write_manifest(self.first, self.one)
        with self.assertRaisesRegex(publisher.PublicationError, "Fedora 44"):
            self.publish_first()

    def test_candidate_symlinks_hardlinks_and_unlisted_files_are_rejected(self):
        target = self.first / "unlisted"
        target.symlink_to(self.second / publisher.MANIFEST)
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        target.unlink()
        os.link(self.first / publisher.MANIFEST, target)
        with self.assertRaisesRegex(publisher.PublicationError, "hardlink"):
            self.publish_first()
        target.unlink()
        target.write_text("extra", encoding="utf-8")
        with self.assertRaisesRegex(publisher.PublicationError, "unlisted"):
            self.publish_first()
        self.assertFalse(self.root.exists())

    def test_origin_and_public_symlinks_and_drift_are_rejected(self):
        elsewhere = self.directory / "elsewhere"
        elsewhere.mkdir()
        self.root.symlink_to(elsewhere, target_is_directory=True)
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        self.root.unlink()
        (publisher.public_channel(self.root)).mkdir(parents=True)
        (publisher.public_channel(self.root) / "foreign").write_text("unmanaged")
        with self.assertRaisesRegex(publisher.PublicationError, "unmanaged"):
            self.publish_first()
        shutil.rmtree(self.root)
        self.publish_first()
        target = self.channel / self.one["packages"][0]["path"]
        target.unlink()
        target.symlink_to(self.first / self.one["packages"][0]["path"])
        with self.assertRaisesRegex(publisher.PublicationError, "symlink"):
            self.publish_first()
        target.unlink()
        target.write_bytes(b"drift")
        with self.assertRaisesRegex(publisher.PublicationError, "drifted"):
            self.publish_first()

    def test_archive_rejects_traversal_links_specials_and_duplicates(self):
        for kind in ("traversal", "symlink", "hardlink", "duplicate"):
            with self.subTest(kind=kind):
                archive = io.BytesIO()
                with tarfile.open(fileobj=archive, mode="w") as output:
                    name = "../escape" if kind == "traversal" else publisher.MANIFEST
                    member = tarfile.TarInfo(name)
                    member.size = 2
                    if kind in ("symlink", "hardlink"):
                        member.type = tarfile.SYMTYPE if kind == "symlink" else tarfile.LNKTYPE
                        member.linkname = "/etc/passwd"
                    output.addfile(member, io.BytesIO(b"{}"))
                    if kind == "duplicate":
                        output.addfile(member, io.BytesIO(b"{}"))
                archive.seek(0)
                destination = self.directory / f"archive-{kind}"
                destination.mkdir()
                with self.assertRaises(publisher.PublicationError):
                    publisher.read_archive(archive, destination)

    def test_remote_arguments_are_data_and_pinned_credentials_are_required(self):
        known = self.directory / "known_hosts"
        identity = self.directory / "identity"
        known.write_text("host ssh-ed25519 AAAA", encoding="utf-8")
        identity.write_text("identity", encoding="utf-8")
        args = argparse.Namespace(ssh="publisher@example.invalid", ssh_port=2222,
                                  known_hosts=known, identity_file=identity)
        request = {"root": "/tmp/path with 'quotes';$(touch /tmp/unsafe)", "action": "fetch"}
        command = publisher.ssh_command(args, request)
        self.assertEqual(command[1:3], ["-F", "/dev/null"])
        self.assertIn("StrictHostKeyChecking=yes", command)
        self.assertIn("ForwardAgent=no", command)
        self.assertIn("GlobalKnownHostsFile=/dev/null", command)
        remote = __import__("shlex").split(command[-1])
        self.assertEqual(remote[:2], ["python3", "-c"])
        self.assertEqual(json.loads(base64.urlsafe_b64decode(remote[-1])), request)
        args.identity_file = None
        with self.assertRaisesRegex(publisher.PublicationError, "identity"):
            publisher.ssh_command(args, request)
        args.identity_file = identity
        args.ssh = "publisher@host;touch"
        with self.assertRaises(publisher.PublicationError):
            publisher.ssh_command(args, request)

    def test_expired_recovery_requires_explicit_historical_verification(self):
        expired = self.directory / "expired"
        manifest = fixture(expired, "2.0.0", int(time.time()) - 2592001)

        def interrupt(label):
            if label == "journal":
                raise InterruptedError("expired pending journal")

        with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
            with self.assertRaises(InterruptedError):
                publisher.publish_at(self.root, expired, FPR, "empty")
        key = self.directory / "key.asc"
        key.write_text("synthetic", encoding="utf-8")
        base = argparse.Namespace(root=str(self.root), public_key=key, fingerprint=FPR,
                                  ssh=None, ssh_port=None, identity_file=None,
                                  known_hosts=None, action="recover", dry_run=True,
                                  allow_expired=False)

        def verify(_root, _key, _fingerprint, historical=False, target=publisher.DEFAULT_TARGET):
            if not historical:
                raise publisher.PublicationError("expired repository")
            return manifest

        with mock.patch.object(publisher, "verify_signed", side_effect=verify):
            with self.assertRaisesRegex(publisher.PublicationError, "expired"):
                publisher.run(base)
            base.allow_expired = True
            checked = publisher.run(base)
            self.assertTrue(checked["requiresRefresh"])
            base.dry_run = False
            completed = publisher.run(base)
            self.assertTrue(completed["requiresRefresh"])
            self.assertIn("Immediately", completed["nextAction"])
            self.assertIn("DNF", completed["nextAction"])


class TargetIsolationTests(unittest.TestCase):
    def setUp(self):
        self.temporary = tempfile.TemporaryDirectory(prefix="loopwire-rpm-target-tests-")
        self.directory = Path(self.temporary.name)
        self.root = self.directory / "origin"
        self.fedora = self.directory / "fedora"
        self.opensuse = self.directory / "opensuse"
        self.opensuse_upgrade = self.directory / "opensuse-upgrade"
        self.fedora_manifest = fixture(self.fedora)
        self.opensuse_manifest = fixture(self.opensuse, target=SUSE)
        self.opensuse_upgrade_manifest = fixture(
            self.opensuse_upgrade, "1.1.0", 2, target=SUSE,
        )

    def tearDown(self):
        self.temporary.cleanup()

    def test_target_validation_happens_before_origin_write(self):
        with self.assertRaisesRegex(publisher.PublicationError, "Fedora 44"):
            publisher.publish_at(self.root, self.opensuse, FPR, "empty")
        self.assertFalse(self.root.exists())
        with self.assertRaisesRegex(publisher.PublicationError, "openSUSE"):
            publisher.publish_at(self.root, self.fedora, FPR, "empty", SUSE)
        self.assertFalse(self.root.exists())
        manifest = json.loads((self.opensuse / publisher.MANIFEST).read_text())
        manifest["packages"][0]["sourceRevision"] = "not-a-commit"
        write_manifest(self.opensuse, manifest)
        with self.assertRaisesRegex(publisher.PublicationError, "source revision"):
            publisher.publish_at(self.root, self.opensuse, FPR, "empty", SUSE)
        self.assertFalse(self.root.exists())

    def test_independent_public_state_snapshot_lock_cas_and_idempotence(self):
        publisher.publish_at(self.root, self.fedora, FPR, "empty")
        result = publisher.publish_at(self.root, self.opensuse, FPR, "empty", SUSE)
        self.assertEqual(result["target"], publisher.TARGETS[SUSE]["manifest"])
        self.assertEqual(
            publisher.state(self.root, "current")["revision"],
            self.fedora_manifest["revision"],
        )
        self.assertEqual(
            publisher.state(self.root, "current", SUSE)["revision"],
            self.opensuse_manifest["revision"],
        )
        self.assertTrue((self.root / "snapshots" / self.fedora_manifest["revision"]).is_dir())
        self.assertTrue((publisher.private_channel(self.root, SUSE) / "snapshots"
                         / self.opensuse_manifest["revision"]).is_dir())
        self.assertTrue((publisher.public_channel(self.root) / "repodata/repomd.xml").is_file())
        self.assertTrue((publisher.public_channel(self.root, SUSE)
                         / "repodata/repomd.xml").is_file())
        self.assertEqual(
            publisher.publish_at(self.root, self.opensuse, FPR, "empty", SUSE)["status"],
            "unchanged",
        )
        with self.assertRaisesRegex(publisher.PublicationError, "compare-and-swap"):
            publisher.publish_at(
                self.root, self.opensuse_upgrade, FPR,
                self.fedora_manifest["revision"], SUSE,
            )
        self.assertEqual(
            publisher.state(self.root, "current", SUSE)["revision"],
            self.opensuse_manifest["revision"],
        )

        # A held Fedora writer lock does not serialize the disjoint openSUSE
        # namespace; openSUSE still uses its own exclusive writer lock.
        with publisher.locked(self.root, create=True):
            publisher.publish_at(
                self.root, self.opensuse_upgrade, FPR,
                self.opensuse_manifest["revision"], SUSE,
            )
        with publisher.locked(self.root, create=True, target=SUSE):
            with self.assertRaisesRegex(publisher.PublicationError, "locked"):
                publisher.publish_at(
                    self.root, self.opensuse, FPR,
                    self.opensuse_upgrade_manifest["revision"], SUSE,
                )

    def test_empty_opensuse_fetch_does_not_create_state_beside_fedora(self):
        publisher.publish_at(self.root, self.fedora, FPR, "empty")
        with self.assertRaises(publisher.EmptyRepository):
            with publisher.selected_snapshot(
                    self.root, FPR, target=SUSE):
                pass
        self.assertFalse(publisher.private_channel(self.root, SUSE).exists())
        self.assertEqual(
            publisher.state(self.root, "current")["revision"],
            self.fedora_manifest["revision"],
        )

    def test_opensuse_retention_collision_and_explicit_rollback(self):
        publisher.publish_at(self.root, self.opensuse, FPR, "empty", SUSE)
        publisher.publish_at(
            self.root, self.opensuse_upgrade, FPR,
            self.opensuse_manifest["revision"], SUSE,
        )
        channel = publisher.public_channel(self.root, SUSE)
        old_package = self.opensuse_manifest["packages"][0]["path"]
        new_package = self.opensuse_upgrade_manifest["packages"][0]["path"]
        self.assertTrue((channel / old_package).is_file())
        self.assertTrue((channel / new_package).is_file())

        collision = self.directory / "collision"
        collision_manifest = fixture(
            collision, "1.1.0", 3, b"changed bytes at an immutable openSUSE URL",
            target=SUSE,
        )
        with self.assertRaisesRegex(publisher.PublicationError, "immutable URL collision"):
            publisher.publish_at(
                self.root, collision, FPR,
                self.opensuse_upgrade_manifest["revision"], SUSE,
            )
        self.assertFalse((publisher.private_channel(self.root, SUSE) / "snapshots"
                          / collision_manifest["revision"]).exists())

        rollback = self.directory / "rollback"
        rollback_manifest = fixture(rollback, "1.0.0", 4, target=SUSE)
        publisher.publish_at(
            self.root, rollback, FPR,
            self.opensuse_upgrade_manifest["revision"], SUSE,
        )
        self.assertEqual(
            publisher.state(self.root, "current", SUSE)["revision"],
            rollback_manifest["revision"],
        )
        self.assertTrue((channel / new_package).is_file(),
                        "rollback must retain newer immutable package URLs")

    def test_every_opensuse_checkpoint_recovers_without_fedora_state(self):
        checkpoints = ("journal", "immutable", "signature", "committed", "manifest", "current")
        for index, checkpoint in enumerate(checkpoints):
            with self.subTest(checkpoint=checkpoint):
                root = self.directory / f"interrupted-{index}"

                def interrupt(label):
                    if label == checkpoint:
                        raise InterruptedError("openSUSE publication interrupted")

                with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                    with self.assertRaises(InterruptedError):
                        publisher.publish_at(root, self.opensuse, FPR, "empty", SUSE)
                self.assertIsNone(publisher.state(root, "current"))
                self.assertEqual(
                    publisher.state(root, "pending", SUSE)["revision"],
                    self.opensuse_manifest["revision"],
                )
                publisher.recover_at(root, FPR, self.opensuse_manifest["revision"], SUSE)
                self.assertEqual(
                    publisher.state(root, "current", SUSE)["revision"],
                    self.opensuse_manifest["revision"],
                )
                self.assertIsNone(publisher.state(root, "pending", SUSE))

    def test_opensuse_private_paths_ignore_restrictive_umask(self):
        previous_umask = os.umask(0o077)
        try:
            publisher.publish_at(self.root, self.opensuse, FPR, "empty", SUSE)
        finally:
            os.umask(previous_umask)
        private = publisher.private_channel(self.root, SUSE)
        self.assertEqual(stat.S_IMODE((self.root / "channels").stat().st_mode), 0o700)
        for path in (private, *private.rglob("*")):
            expected = 0o700 if path.is_dir() else 0o600
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), expected, str(path))
        public = publisher.public_channel(self.root, SUSE)
        for path in (public, *public.rglob("*")):
            expected = 0o755 if path.is_dir() else 0o644
            self.assertEqual(stat.S_IMODE(path.stat().st_mode), expected, str(path))

    def test_expired_opensuse_recovery_names_zypper_refresh_boundary(self):
        expired = self.directory / "opensuse-expired"
        manifest = fixture(
            expired, "2.0.0", int(time.time()) - 2592001, target=SUSE,
        )

        def interrupt(label):
            if label == "journal":
                raise InterruptedError("expired openSUSE pending journal")

        with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
            with self.assertRaises(InterruptedError):
                publisher.publish_at(self.root, expired, FPR, "empty", SUSE)
        key = self.directory / "opensuse-key.asc"
        key.write_text("synthetic", encoding="utf-8")
        args = argparse.Namespace(
            root=str(self.root), public_key=key, fingerprint=FPR,
            target=SUSE, ssh=None, ssh_port=None, identity_file=None,
            known_hosts=None, action="recover", dry_run=False,
            allow_expired=True,
        )

        def verify(_root, _key, _fingerprint, historical=False, target=None):
            self.assertEqual(target, SUSE)
            self.assertTrue(historical)
            return manifest

        with mock.patch.object(publisher, "verify_signed", side_effect=verify):
            completed = publisher.run(args)
        self.assertTrue(completed["requiresRefresh"])
        self.assertIn("Zypper/libzypp", completed["nextAction"])
        self.assertNotIn("DNF", completed["nextAction"])


class SignedDnfCommitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not WITH_SSH:
            raise unittest.SkipTest("runs with --with-ssh in the pinned RPM tools container")
        required = ("createrepo_c", "dnf", "gpg", "openssl", "rpmbuild", "rpmkeys", "rpmsign")
        missing = [tool for tool in required if shutil.which(tool) is None]
        if missing:
            raise unittest.SkipTest("missing RPM tools: " + ", ".join(missing))
        cls.temporary = tempfile.TemporaryDirectory(prefix="loopwire-rpm-dnf-tests-")
        cls.directory = Path(cls.temporary.name)
        cls.gnupg = cls.directory / "gnupg"
        cls.gnupg.mkdir(mode=0o700)
        cls.date = int(time.time()) - 120
        cls.shell(
            "gpg", "--homedir", cls.gnupg, "--batch", "--pinentry-mode", "loopback",
            "--passphrase", "", "--faked-system-time", f"{cls.date - 60}!",
            "--quick-generate-key", "Loopwire Fedora publisher fixture", "rsa2048", "sign", "1y",
        )
        listing = cls.shell("gpg", "--homedir", cls.gnupg, "--with-colons", "--list-keys").stdout
        cls.fingerprint = next(line.split(":")[9] for line in listing.splitlines()
                               if line.startswith("fpr:"))
        cls.public_key = cls.directory / "repository-key.asc"
        cls.public_key.write_text(cls.shell(
            "gpg", "--homedir", cls.gnupg, "--armor", "--export", cls.fingerprint,
        ).stdout, encoding="utf-8")
        cls.release_private = cls.directory / "release-private.pem"
        cls.release_public = cls.directory / "release-public.pem"
        cls.shell("openssl", "genpkey", "-algorithm", "RSA", "-pkeyopt", "rsa_keygen_bits:2048",
                "-out", cls.release_private)
        cls.shell("openssl", "pkey", "-in", cls.release_private, "-pubout",
                "-out", cls.release_public)
        cls.first = cls.build_candidate("1.0.0", cls.date)
        cls.second = cls.build_candidate("1.1.0", cls.date + 1, cls.first)
        cls.one = json.loads((cls.first / publisher.MANIFEST).read_text(encoding="utf-8"))
        cls.two = json.loads((cls.second / publisher.MANIFEST).read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "gnupg"):
            subprocess.run(["gpgconf", "--homedir", str(cls.gnupg), "--kill", "gpg-agent"],
                           check=False, capture_output=True)
        if hasattr(cls, "temporary"):
            cls.temporary.cleanup()

    @classmethod
    def shell(cls, *command, cwd=None, ok=True):
        result = subprocess.run(list(map(str, command)), cwd=cwd, capture_output=True,
                                text=True, check=False)
        if ok and result.returncode != 0:
            raise AssertionError("command failed: " + " ".join(map(str, command))
                                 + "\n" + result.stdout + result.stderr)
        return result

    @classmethod
    def build_rpm(cls, version, release):
        top = cls.directory / f"rpmbuild-{version}"
        for child in ("BUILD", "BUILDROOT", "RPMS", "SOURCES", "SPECS", "SRPMS"):
            (top / child).mkdir(parents=True)
        spec = top / "SPECS/loopwire.spec"
        spec.write_text(
            "Name: loopwire\n"
            f"Version: {version}\n"
            "Release: 1.fc44\nSummary: DNF publisher fixture\n"
            "License: MIT\nBuildArch: x86_64\n\n"
            "%description\nDNF publisher fixture.\n\n"
            "%prep\n\n%build\n\n"
            "%install\nmkdir -p %{buildroot}/usr/bin\n"
            f"printf '#!/bin/sh\\necho {version}\\n' > %{{buildroot}}/usr/bin/loopwire\n"
            "chmod 0755 %{buildroot}/usr/bin/loopwire\n\n"
            "%files\n/usr/bin/loopwire\n",
            encoding="utf-8",
        )
        cls.shell("rpmbuild", "-bb", "--define", f"_topdir {top}", spec)
        built = top / f"RPMS/x86_64/loopwire-{version}-1.fc44.x86_64.rpm"
        release.mkdir()
        target = release / built.name
        shutil.copyfile(built, target)
        checksums = release / "SHA256SUMS"
        checksums.write_text(f"{publisher.digest(target)}  {target.name}\n", encoding="utf-8")
        cls.shell("openssl", "dgst", "-sha256", "-sign", cls.release_private,
                "-out", release / "SHA256SUMS.sig", checksums)

    @classmethod
    def build_candidate(cls, version, date, previous=None):
        release = cls.directory / f"release-{version}"
        cls.build_rpm(version, release)
        candidate = cls.directory / f"candidate-{version}"
        command = [
            sys.executable, SCRIPT.with_name("rpm-repository.py"), "build",
            "--release-dir", release, "--version", version, "--output", candidate,
            "--signing-key", cls.fingerprint, "--gnupg-home", cls.gnupg,
            "--date", str(date), "--valid-for-days", "30",
            "--release-public-key", cls.release_public,
        ]
        if previous:
            command += ["--previous", previous]
        cls.shell(*command)
        return candidate

    def setUp(self):
        self.origin = self.directory / self.id().split(".")[-1]

    def publisher_cli(self, action, *extra, ok=True):
        root = self.origin / "origin"
        result = self.shell(
            sys.executable, SCRIPT, action, "--root", root,
            "--public-key", self.public_key, "--fingerprint", self.fingerprint,
            *extra, ok=False,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def dnf_query(self, label):
        repos = self.origin / f"repos-{label}"
        cache = self.origin / f"cache-{label}"
        persist = self.origin / f"persist-{label}"
        repos.mkdir(parents=True)
        channel = publisher.public_channel(self.origin / "origin")
        (repos / "loopwire.repo").write_text(
            "[loopwire]\nname=Loopwire test\nenabled=1\n"
            f"baseurl=file://{channel}/\n"
            "gpgcheck=1\nrepo_gpgcheck=1\n"
            f"gpgkey=file://{channel}/keys/{self.fingerprint}.asc\n"
            "metadata_expire=0\n",
            encoding="utf-8",
        )
        return self.shell(
            "dnf", "-y", "--setopt", f"reposdir={repos}",
            "--setopt", f"cachedir={cache}", "--setopt", f"persistdir={persist}",
            "--disablerepo=*", "--enablerepo=loopwire", "repoquery", "loopwire",
            ok=False,
        )

    def test_real_dnf_rejects_interrupted_signature_xml_pair_and_accepts_recovery(self):
        root = self.origin / "origin"
        publisher.publish_at(root, self.first, self.fingerprint, "empty")
        initial = self.dnf_query("initial")
        self.assertEqual(initial.returncode, 0, initial.stdout + initial.stderr)
        self.assertIn("loopwire-0:", initial.stdout)

        def interrupt(label):
            if label == "signature":
                raise InterruptedError("leave new signature with old repomd.xml")

        with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
            with self.assertRaises(InterruptedError):
                publisher.publish_at(root, self.second, self.fingerprint, self.one["revision"])
        mixed = self.dnf_query("mixed")
        # DNF5 currently exits zero after excluding a repository whose metadata
        # signature failed, so package absence plus its explicit verification
        # diagnostic is the acceptance boundary.
        self.assertIn("Bad PGP signature", mixed.stdout + mixed.stderr)
        self.assertNotIn("loopwire-0:", mixed.stdout)
        publisher.recover_at(root, self.fingerprint, self.two["revision"])
        recovered = self.dnf_query("recovered")
        self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
        self.assertIn("loopwire-0:", recovered.stdout)

    def test_signed_cli_publish_fetch_idempotence_and_retained_revision(self):
        dry = self.publisher_cli(
            "publish", "--repository", self.first, "--expected-revision", "empty",
            "--dry-run",
        )
        self.assertEqual(json.loads(dry.stdout)["status"], "validated")
        self.assertFalse((self.origin / "origin").exists())
        first = self.publisher_cli(
            "publish", "--repository", self.first, "--expected-revision", "empty",
        )
        self.assertEqual(json.loads(first.stdout)["revision"], self.one["revision"])
        unchanged = self.publisher_cli(
            "publish", "--repository", self.first, "--expected-revision", "empty",
        )
        self.assertEqual(json.loads(unchanged.stdout)["status"], "unchanged")
        self.publisher_cli(
            "publish", "--repository", self.second,
            "--expected-revision", self.one["revision"],
        )
        current = self.origin / "current"
        fetched = self.publisher_cli("fetch", "--output", current)
        self.assertEqual(json.loads(fetched.stdout)["revision"], self.two["revision"])
        retained = self.origin / "retained"
        fetched = self.publisher_cli(
            "fetch", "--output", retained, "--revision", self.one["revision"],
        )
        self.assertEqual(json.loads(fetched.stdout)["revision"], self.one["revision"])
        self.assertEqual((retained / publisher.MANIFEST).read_bytes(),
                         (self.first / publisher.MANIFEST).read_bytes())


class SignedZypperCommitTests(unittest.TestCase):
    @classmethod
    def setUpClass(cls):
        if not WITH_SSH:
            raise unittest.SkipTest("runs with --with-ssh in the pinned openSUSE tools container")
        fixtures = load(
            "opensuse_repository_test_fixtures",
            SCRIPT.with_name("test-rpm-repository.py"),
        ).OpenSUSERepositoryTests
        fixtures.setUpClass()
        cls.fixtures = fixtures
        cls.directory = fixtures.root / "publisher-integration"
        cls.directory.mkdir()
        cls.gnupg = fixtures.gnupg
        cls.fingerprint = fixtures.fingerprint
        cls.public_key = fixtures.key
        cls.date = fixtures.date
        cls.first = fixtures.base
        cls.second = cls.directory / "candidate-opensuse-1.1.0"
        fixtures.build(
            fixtures.release2, "1.1.0", cls.second,
            "--previous", cls.first, "--date", str(cls.date + 1),
        )
        cls.rollback = cls.directory / "candidate-rollback"
        cls.shell(
            sys.executable, SCRIPT.with_name("rpm-repository.py"), "rollback",
            "--repository", cls.first, "--target", SUSE,
            "--output", cls.rollback, "--signing-key", cls.fingerprint,
            "--gnupg-home", cls.gnupg, "--date", str(cls.date + 2),
            "--valid-for-days", "30",
        )
        cls.one = json.loads((cls.first / publisher.MANIFEST).read_text(encoding="utf-8"))
        cls.two = json.loads((cls.second / publisher.MANIFEST).read_text(encoding="utf-8"))
        cls.rolled = json.loads((cls.rollback / publisher.MANIFEST).read_text(encoding="utf-8"))

    @classmethod
    def tearDownClass(cls):
        if hasattr(cls, "fixtures"):
            cls.fixtures.tearDownClass()

    @classmethod
    def shell(cls, *command, cwd=None, ok=True):
        result = subprocess.run(
            list(map(str, command)), cwd=cwd, capture_output=True,
            text=True, check=False,
        )
        if ok and result.returncode != 0:
            raise AssertionError(
                "command failed: " + " ".join(map(str, command))
                + "\n" + result.stdout + result.stderr
            )
        return result

    def setUp(self):
        self.case_dir = self.directory / self.id().split(".")[-1]
        self.case_dir.mkdir()
        self.root = self.case_dir / "origin"

    def publisher_cli(self, action, *extra, ok=True):
        result = self.shell(
            sys.executable, SCRIPT, action, "--target", SUSE,
            "--root", self.root, "--public-key", self.public_key,
            "--fingerprint", self.fingerprint, *extra, ok=False,
        )
        if ok:
            self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        return result

    def zypper(self, label, command, base_url=None):
        state = self.case_dir / f"zypper-{label}"
        repos = state / "repos"
        for path in (state, repos, state / "cache", state / "raw", state / "solv", state / "packages"):
            path.mkdir(exist_ok=True)
        channel = publisher.public_channel(self.root, SUSE)
        base_url = base_url or f"file://{channel}/"
        key_url = base_url + f"keys/{self.fingerprint}.asc"
        (repos / "loopwire.repo").write_text(
            "[loopwire]\nname=Loopwire test\nenabled=1\nautorefresh=0\ntype=rpm-md\n"
            f"baseurl={base_url}\n"
            f"gpgkey={key_url}\n"
            "gpgcheck=1\nrepo_gpgcheck=1\npkg_gpgcheck=1\n",
            encoding="utf-8",
        )
        args = [
            "zypper", "--non-interactive", "--gpg-auto-import-keys",
            "--disable-system-resolvables", "--reposd-dir", repos,
            "--cache-dir", state / "cache", "--raw-cache-dir", state / "raw",
            "--solv-cache-dir", state / "solv", "--pkg-cache-dir", state / "packages",
        ]
        return self.shell(*args, *command, ok=False)

    def test_signed_cli_publish_fetch_upgrade_retention_and_rollback(self):
        dry = self.publisher_cli(
            "publish", "--repository", self.first,
            "--expected-revision", "empty", "--dry-run",
        )
        self.assertEqual(json.loads(dry.stdout)["status"], "validated")
        self.assertFalse(self.root.exists())
        self.publisher_cli(
            "publish", "--repository", self.first, "--expected-revision", "empty",
        )
        fetched = self.case_dir / "fetched"
        self.publisher_cli("fetch", "--output", fetched)
        self.assertEqual((fetched / publisher.MANIFEST).read_bytes(),
                         (self.first / publisher.MANIFEST).read_bytes())
        self.publisher_cli(
            "publish", "--repository", self.second,
            "--expected-revision", self.one["revision"],
        )
        self.publisher_cli(
            "publish", "--repository", self.rollback,
            "--expected-revision", self.two["revision"],
        )
        channel = publisher.public_channel(self.root, SUSE)
        for manifest in (self.one, self.two):
            for package in manifest["packages"]:
                self.assertTrue((channel / package["path"]).is_file())
        self.assertEqual(
            publisher.state(self.root, "current", SUSE)["revision"],
            self.rolled["revision"],
        )

    def test_real_zypper_rejects_mixed_metadata_then_accepts_recovery_and_rollback(self):
        publisher.publish_at(self.root, self.first, self.fingerprint, "empty", SUSE)
        handler = functools.partial(
            QuietHttpHandler, directory=str(self.root / "public"),
        )
        server = http.server.ThreadingHTTPServer(("127.0.0.1", 0), handler)
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        base_url = (
            f"http://127.0.0.1:{server.server_port}/opensuse/tumbleweed/x86_64/"
        )
        try:
            refreshed = self.zypper("initial", ["refresh"], base_url)
            self.assertEqual(refreshed.returncode, 0, refreshed.stdout + refreshed.stderr)
            searched = self.zypper(
                "initial-search", ["search", "--details", "loopwire"], base_url,
            )
            self.assertEqual(searched.returncode, 0, searched.stdout + searched.stderr)
            self.assertIn("1.0.0", searched.stdout)

            def interrupt(label):
                if label == "signature":
                    raise InterruptedError("leave new signature with old repomd.xml")

            with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                with self.assertRaises(InterruptedError):
                    publisher.publish_at(
                        self.root, self.second, self.fingerprint,
                        self.one["revision"], SUSE,
                    )
            mixed = self.zypper("mixed", ["refresh"], base_url)
            self.assertNotEqual(mixed.returncode, 0, mixed.stdout + mixed.stderr)
            self.assertRegex(
                mixed.stdout + mixed.stderr,
                r"(?i)(signature|verification).*(fail|invalid)",
            )

            publisher.recover_at(self.root, self.fingerprint, self.two["revision"], SUSE)
            recovered = self.zypper("recovered", ["refresh"], base_url)
            self.assertEqual(recovered.returncode, 0, recovered.stdout + recovered.stderr)
            searched = self.zypper(
                "recovered-search", ["search", "--details", "loopwire"], base_url,
            )
            self.assertIn("1.1.0", searched.stdout)

            publisher.publish_at(
                self.root, self.rollback, self.fingerprint,
                self.two["revision"], SUSE,
            )
            rolled = self.zypper("rollback", ["refresh"], base_url)
            self.assertEqual(rolled.returncode, 0, rolled.stdout + rolled.stderr)
            searched = self.zypper(
                "rollback-search", ["search", "--details", "loopwire"], base_url,
            )
            self.assertIn("1.0.0", searched.stdout)
            self.assertNotIn("1.1.0", searched.stdout)
        finally:
            server.shutdown()
            server.server_close()
            thread.join()


class SshPublicationTests(unittest.TestCase):
    def test_actual_ssh_publish_fetch_and_recover_without_remote_gpg(self):
        if not WITH_SSH:
            self.skipTest("use --with-ssh inside the pinned disposable RPM tools container")
        self.assertTrue(Path("/.dockerenv").exists() and os.geteuid() == 0,
                        "--with-ssh is restricted to root in a disposable container")
        sshd = shutil.which("sshd")
        self.assertIsNotNone(sshd, "openssh-server is required")
        # Fedora's container root account is locked by default. Unlock it only
        # inside this disposable container; sshd still permits public-key auth
        # exclusively and listens on a random loopback port.
        unlocked = subprocess.run(["passwd", "-d", "root"], capture_output=True,
                                  text=True, check=False)
        self.assertEqual(unlocked.returncode, 0, unlocked.stderr)
        with tempfile.TemporaryDirectory(prefix="loopwire-rpm-ssh-tests-") as temporary:
            directory = Path(temporary)
            first = directory / "first"
            second = directory / "second"
            one = fixture(first)
            two = fixture(second, "1.1.0", 2)
            opensuse_first = directory / "opensuse-first"
            opensuse_second = directory / "opensuse-second"
            opensuse_one = fixture(opensuse_first, target=SUSE)
            opensuse_two = fixture(opensuse_second, "1.1.0", 2, target=SUSE)
            origin = directory / "origin"
            identity = directory / "identity"
            host_key = directory / "host-key"
            for key in (identity, host_key):
                subprocess.run(["ssh-keygen", "-q", "-t", "ed25519", "-N", "",
                                "-f", str(key)], check=True)
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            known = directory / "known_hosts"
            known.write_text(f"[127.0.0.1]:{port} " + host_key.with_suffix(".pub").read_text())
            remote_bin = directory / "remote-bin"
            remote_bin.mkdir()
            (remote_bin / "python3").symlink_to(sys.executable)
            force_command = directory / "force-command"
            force_command.write_text(
                "#!/bin/sh\n"
                f"PATH={remote_bin} exec /bin/sh -c \"$SSH_ORIGINAL_COMMAND\"\n",
                encoding="utf-8",
            )
            force_command.chmod(0o700)
            configuration = directory / "sshd.conf"
            configuration.write_text(
                f"Port {port}\nListenAddress 127.0.0.1\nHostKey {host_key}\n"
                f"PidFile {directory / 'sshd.pid'}\nAuthorizedKeysFile {identity}.pub\n"
                "PermitRootLogin prohibit-password\nPasswordAuthentication no\n"
                "KbdInteractiveAuthentication no\nUsePAM no\nStrictModes no\nAllowUsers root\n"
                f"LogLevel ERROR\nForceCommand {force_command}\n")
            Path("/run/sshd").mkdir(exist_ok=True)
            with (directory / "sshd.log").open("wb") as log:
                server = subprocess.Popen([sshd, "-D", "-e", "-f", str(configuration)],
                                          stdout=log, stderr=log)
                try:
                    for _ in range(100):
                        self.assertIsNone(server.poll(), "temporary sshd exited")
                        try:
                            with socket.create_connection(("127.0.0.1", port), timeout=0.1):
                                break
                        except OSError:
                            time.sleep(0.05)
                    connection = argparse.Namespace(
                        ssh="root@127.0.0.1", ssh_port=port,
                        identity_file=identity, known_hosts=known,
                    )
                    probe = publisher.ssh_command(connection, {})
                    probe[-1] = "python3 -c 'import shutil; assert shutil.which(\"gpg\") is None'"
                    result = subprocess.run(probe, capture_output=True, text=True, check=False)
                    self.assertEqual(result.returncode, 0, result.stderr)
                    result = publisher.remote_call(connection, {
                        "action": "publish", "root": str(origin), "fingerprint": FPR,
                        "expected": "empty",
                    }, repository=first)
                    self.assertEqual(result["revision"], one["revision"])
                    fetched = directory / "fetched"
                    fetched.mkdir()
                    publisher.remote_call(connection, {
                        "action": "fetch", "root": str(origin), "fingerprint": FPR,
                        "revision": None,
                    }, output=fetched)
                    self.assertEqual((fetched / publisher.MANIFEST).read_bytes(),
                                     (first / publisher.MANIFEST).read_bytes())
                    def interrupt(label):
                        if label == "signature":
                            raise InterruptedError("simulate remote process loss")

                    with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                        with self.assertRaises(InterruptedError):
                            publisher.publish_at(origin, second, FPR, one["revision"])
                    pending = directory / "pending"
                    pending.mkdir()
                    publisher.remote_call(connection, {
                        "action": "fetch-pending", "root": str(origin),
                        "fingerprint": FPR, "revision": None,
                    }, output=pending)
                    self.assertEqual((pending / publisher.MANIFEST).read_bytes(),
                                     (second / publisher.MANIFEST).read_bytes())
                    result = publisher.remote_call(connection, {
                        "action": "recover", "root": str(origin), "fingerprint": FPR,
                        "revision": two["revision"],
                    })
                    self.assertEqual(result["revision"], two["revision"])
                    self.assertIsNone(publisher.state(origin, "pending"))

                    result = publisher.remote_call(connection, {
                        "action": "publish", "root": str(origin), "target": SUSE,
                        "fingerprint": FPR, "expected": "empty",
                    }, repository=opensuse_first)
                    self.assertEqual(result["revision"], opensuse_one["revision"])
                    opensuse_fetched = directory / "opensuse-fetched"
                    opensuse_fetched.mkdir()
                    publisher.remote_call(connection, {
                        "action": "fetch", "root": str(origin), "target": SUSE,
                        "fingerprint": FPR, "revision": None,
                    }, output=opensuse_fetched)
                    self.assertEqual(
                        (opensuse_fetched / publisher.MANIFEST).read_bytes(),
                        (opensuse_first / publisher.MANIFEST).read_bytes(),
                    )
                    with mock.patch.object(publisher, "_checkpoint", side_effect=interrupt):
                        with self.assertRaises(InterruptedError):
                            publisher.publish_at(
                                origin, opensuse_second, FPR,
                                opensuse_one["revision"], SUSE,
                            )
                    opensuse_pending = directory / "opensuse-pending"
                    opensuse_pending.mkdir()
                    publisher.remote_call(connection, {
                        "action": "fetch-pending", "root": str(origin), "target": SUSE,
                        "fingerprint": FPR, "revision": None,
                    }, output=opensuse_pending)
                    result = publisher.remote_call(connection, {
                        "action": "recover", "root": str(origin), "target": SUSE,
                        "fingerprint": FPR, "revision": opensuse_two["revision"],
                    })
                    self.assertEqual(result["revision"], opensuse_two["revision"])
                    self.assertIsNone(publisher.state(origin, "pending", SUSE))
                    self.assertEqual(
                        publisher.state(origin, "current")["revision"], two["revision"],
                        "openSUSE SSH operations must not alter Fedora state",
                    )
                    known.write_text("", encoding="utf-8")
                    with self.assertRaisesRegex(publisher.PublicationError, "SSH"):
                        publisher.remote_call(connection, {
                            "action": "fetch", "root": str(origin), "fingerprint": FPR,
                            "revision": None,
                        }, output=directory / "untrusted")
                finally:
                    server.terminate()
                    server.wait(timeout=10)


class NginxPublicTests(unittest.TestCase):
    def test_syntax_and_live_cache_headers(self):
        if not WITH_SSH:
            self.skipTest("runs with --with-ssh in the pinned RPM tools container")
        nginx = shutil.which("nginx")
        self.assertIsNotNone(nginx, "nginx is required")
        snippet_path = (SCRIPT.parent.parent / "packaging/repositories/nginx-rpm.conf")
        with tempfile.TemporaryDirectory(prefix="loopwire-rpm-nginx-tests-") as temporary:
            directory = Path(temporary)
            origin = directory / "origin"
            candidate = directory / "candidate"
            manifest = fixture(candidate)
            opensuse_candidate = directory / "opensuse-candidate"
            opensuse_manifest = fixture(opensuse_candidate, target=SUSE)
            publisher.publish_at(origin, candidate, FPR, "empty")
            publisher.publish_at(origin, opensuse_candidate, FPR, "empty", SUSE)
            snippet = directory / "nginx-rpm.conf"
            snippet.write_text(
                snippet_path.read_text(encoding="utf-8").replace(
                    "/srv/loopwire-rpm", str(origin)), encoding="utf-8")
            with socket.socket() as listener:
                listener.bind(("127.0.0.1", 0))
                port = listener.getsockname()[1]
            config = directory / "nginx.conf"
            config.write_text(
                "user root;\nworker_processes 1;\nerror_log stderr notice;\n"
                f"pid {directory / 'nginx.pid'};\nevents {{ worker_connections 64; }}\n"
                "http { access_log off; server { "
                f"listen 127.0.0.1:{port}; include {snippet};"
                " } }\n", encoding="utf-8")
            checked = subprocess.run([nginx, "-t", "-c", str(config)],
                                     capture_output=True, text=True, check=False)
            self.assertEqual(checked.returncode, 0, checked.stderr)
            server = subprocess.Popen([nginx, "-c", str(config), "-g", "daemon off;"],
                                      stdout=subprocess.DEVNULL, stderr=subprocess.PIPE,
                                      text=True)
            try:
                host = f"http://127.0.0.1:{port}/"
                base = host + "fedora/44/x86_64/"
                for _ in range(100):
                    try:
                        urllib.request.urlopen(base + "repodata/repomd.xml", timeout=0.1).close()
                        break
                    except (OSError, urllib.error.URLError):
                        if server.poll() is not None:
                            self.fail(server.stderr.read())
                        time.sleep(0.02)

                def headers(base_url, path):
                    with urllib.request.urlopen(base_url + path, timeout=2) as response:
                        self.assertEqual(response.status, 200)
                        return response.headers

                self.assertIn("no-store", headers(base, "repodata/repomd.xml")["Cache-Control"])
                self.assertIn("no-store", headers(base, "repodata/repomd.xml.asc")["Cache-Control"])
                package = manifest["packages"][0]["path"]
                self.assertIn("immutable", headers(base, package)["Cache-Control"])
                hashed = next(entry["path"] for entry in manifest["files"]
                              if entry["path"].endswith("primary.xml.gz"))
                self.assertIn("immutable", headers(base, hashed)["Cache-Control"])
                with self.assertRaises(urllib.error.HTTPError) as missing:
                    urllib.request.urlopen(base +
                        "packages/loopwire-9.9.9-1.fc44.x86_64.rpm", timeout=2)
                self.assertEqual(missing.exception.code, 404)
                self.assertIn("no-store", missing.exception.headers["Cache-Control"])
                missing.exception.close()

                opensuse_base = host + "opensuse/tumbleweed/x86_64/"
                self.assertIn("no-store", headers(
                    opensuse_base, "repodata/repomd.xml")["Cache-Control"])
                self.assertIn("no-store", headers(
                    opensuse_base, "repodata/repomd.xml.asc")["Cache-Control"])
                self.assertIn("immutable", headers(
                    opensuse_base,
                    opensuse_manifest["packages"][0]["path"],
                )["Cache-Control"])
                opensuse_hashed = next(
                    entry["path"] for entry in opensuse_manifest["files"]
                    if entry["path"].endswith("primary.xml.gz")
                )
                self.assertIn("immutable", headers(
                    opensuse_base, opensuse_hashed)["Cache-Control"])
                with self.assertRaises(urllib.error.HTTPError) as opensuse_missing:
                    urllib.request.urlopen(
                        opensuse_base + "packages/loopwire-9.9.9-1.x86_64.rpm",
                        timeout=2,
                    )
                self.assertEqual(opensuse_missing.exception.code, 404)
                self.assertIn("no-store", opensuse_missing.exception.headers["Cache-Control"])
                opensuse_missing.exception.close()
            finally:
                server.terminate()
                server.wait(timeout=10)
                server.stderr.close()


if __name__ == "__main__":
    if "--with-ssh" in sys.argv:
        WITH_SSH = True
        sys.argv.remove("--with-ssh")
    unittest.main(verbosity=2)
