#!/usr/bin/env python3
"""Publish verified Fedora and openSUSE RPM repositories to a POSIX origin.

ROOT/public is the HTTP document root. Supported base URLs are
ROOT/public/fedora/44/x86_64 and ROOT/public/opensuse/tumbleweed/x86_64.
Fedora keeps its existing private ROOT/state and ROOT/snapshots paths. openSUSE
uses ROOT/channels/opensuse-tumbleweed-x86_64/{state,snapshots} so locks, journals,
revisions, and rollback inputs remain independent. Package, key, and
checksum-named repodata URLs are immutable and retained within each namespace.

RPM metadata uses a fail-closed commit protocol: repomd.xml.asc is replaced
first and repomd.xml is replaced atomically last.  A client crossing that
boundary can observe a signature mismatch, but repo_gpgcheck=1 cannot accept a
partially published repository.  The durable pending journal must be completed
before another revision may be published.

The SSH transport executes this same source with Python 3 on the origin.  The
client verifies OpenPGP signatures; no signing key or GPG program is sent to the
origin.  Remote use requires a pinned known_hosts file and an explicit identity
file.  The origin filesystem must implement flock, fsync, and same-directory
atomic rename.
"""

import argparse
import base64
import contextlib
import fcntl
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shlex
import shutil
import stat
import subprocess
import sys
import tarfile
import tempfile
import time


MANIFEST = "repository-manifest.json"
SCHEMA = "loopwire.rpm-repository.v1"
DEFAULT_TARGET = "fedora-44-x86_64"
TARGETS = {
    DEFAULT_TARGET: {
        "manifest": {"distribution": "fedora", "release": "44", "architecture": "x86_64"},
        "publicPrefix": Path("fedora/44/x86_64"),
        "packageRelease": "1.fc44",
        "sourceRevision": False,
        "packagePattern": re.compile(
            r"packages/loopwire-{version}-1\.fc44\.x86_64\.rpm\Z"
        ),
        "label": "Fedora 44 x86_64",
        "client": "DNF",
    },
    "opensuse-tumbleweed-x86_64": {
        "manifest": {
            "distribution": "opensuse", "release": "tumbleweed", "architecture": "x86_64",
        },
        "publicPrefix": Path("opensuse/tumbleweed/x86_64"),
        "packageRelease": "1",
        "sourceRevision": True,
        "packagePattern": re.compile(
            r"packages/loopwire-{version}-1\.x86_64\.rpm\Z"
        ),
        "label": "openSUSE Tumbleweed x86_64",
        "client": "Zypper/libzypp",
    },
}
REVISION = re.compile(r"[0-9a-f]{64}\Z")
FINGERPRINT = re.compile(r"(?:[A-F0-9]{40}|[A-F0-9]{64})\Z")
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\+[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?"
REPODATA_PATH = re.compile(
    r"repodata/[0-9a-f]{64}-(?:primary|filelists|other)\.xml\.gz\Z"
)
# Compatibility aliases for existing Fedora callers and tests.
TARGET = TARGETS[DEFAULT_TARGET]["manifest"]
PUBLIC_PREFIX = TARGETS[DEFAULT_TARGET]["publicPrefix"]
PACKAGE_PATH = re.compile(rf"packages/loopwire-{VERSION}-1\.fc44\.x86_64\.rpm\Z")
MANIFEST_FIELDS = {
    "schema", "schemaVersion", "revision", "signingFingerprint",
    "createdAt", "validUntil", "target", "packages", "files",
}
PACKAGE_FIELDS = {
    "name", "version", "release", "architecture", "path",
    "sourceReleaseSha256", "distributedSha256", "size",
}
FILE_FIELDS = {"path", "sha256", "size", "kind"}


class PublicationError(Exception):
    """An actionable publication failure without private transport details."""


class EmptyRepository(PublicationError):
    """No committed snapshot exists (distinct exit status 3)."""


def require(condition, message):
    if not condition:
        raise PublicationError(message)


def target_config(target=DEFAULT_TARGET):
    require(isinstance(target, str) and target in TARGETS,
            "unsupported RPM repository target")
    config = TARGETS[target]
    pattern = config["packagePattern"].pattern.format(version=VERSION)
    return target, config, re.compile(pattern)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, "duplicate repository JSON field")
        result[key] = value
    return result


def digest(path):
    with path.open("rb") as source:
        if hasattr(hashlib, "file_digest"):
            return hashlib.file_digest(source, "sha256").hexdigest()
        result = hashlib.sha256()
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            result.update(chunk)
        return result.hexdigest()


def safe_path(value):
    require(isinstance(value, str) and value and "\\" not in value,
            "inventory contains an invalid path")
    path = PurePosixPath(value)
    require(not path.is_absolute() and path.as_posix() == value
            and all(part not in (".", "..") for part in path.parts),
            "inventory path must be normalized and relative")
    return path


def classify(path, target=DEFAULT_TARGET):
    """Derive URL mutability from the protocol, never from manifest input."""
    safe_path(path)
    _target, _config, package_path = target_config(target)
    if package_path.fullmatch(path):
        return "immutable"
    if re.fullmatch(r"keys/(?:[A-F0-9]{40}|[A-F0-9]{64})\.asc", path):
        return "immutable"
    if REPODATA_PATH.fullmatch(path):
        return "immutable"
    if path in ("repodata/repomd.xml", "repodata/repomd.xml.asc"):
        return "metadata"
    raise PublicationError("inventory contains a path outside the selected RPM protocol")


def plain_path(path, directory=False, missing=False):
    """Reject symlinks in every existing ancestor, including origin roots."""
    path = Path(path).absolute()
    require(".." not in path.parts, "paths must not contain parent traversal")
    for item in reversed((path, *path.parents)):
        try:
            mode = item.lstat().st_mode
        except FileNotFoundError:
            if missing:
                continue
            raise PublicationError("required path does not exist") from None
        require(not stat.S_ISLNK(mode), "symlinks are forbidden in repository paths")
        if item != path or directory:
            require(stat.S_ISDIR(mode), "repository ancestor is not a directory")
    return path


def tree_files(root):
    root = plain_path(root, directory=True)
    result = set()
    for directory, dirs, files in os.walk(root, followlinks=False):
        for name in dirs + files:
            item = Path(directory) / name
            info = item.lstat()
            require(not stat.S_ISLNK(info.st_mode), "candidate contains a symlink")
            if name in dirs:
                require(stat.S_ISDIR(info.st_mode), "candidate contains a non-directory")
            else:
                require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                        "candidate contains a nonregular file or hardlink")
                result.add(item.relative_to(root).as_posix())
    return result


def read_json(path):
    plain_path(path)
    try:
        with path.open(encoding="utf-8") as source:
            return json.load(source, object_pairs_hook=object_pairs)
    except (ValueError, UnicodeError) as error:
        raise PublicationError("invalid repository JSON") from error


def inventory(root, fingerprint, target=DEFAULT_TARGET):
    target, config, package_path = target_config(target)
    root = plain_path(root, directory=True)
    actual = tree_files(root)
    require(MANIFEST in actual, "candidate is missing its manifest")
    manifest = read_json(root / MANIFEST)
    require(isinstance(manifest, dict) and manifest.get("schema") == SCHEMA
            and manifest.get("schemaVersion") == 1, "unsupported repository manifest")
    require(set(manifest) == MANIFEST_FIELDS, "invalid repository manifest fields")
    revision = manifest.get("revision")
    require(isinstance(revision, str) and REVISION.fullmatch(revision),
            "invalid candidate revision")
    unsigned = {key: value for key, value in manifest.items() if key != "revision"}
    require(hashlib.sha256(canonical(unsigned)).hexdigest() == revision,
            "candidate revision does not match its manifest")
    require(isinstance(fingerprint, str) and FINGERPRINT.fullmatch(fingerprint)
            and manifest.get("signingFingerprint") == fingerprint,
            "candidate signing fingerprint differs")
    require(manifest.get("target") == config["manifest"],
            f"candidate must target {config['label']}")
    require(type(manifest.get("createdAt")) is int and type(manifest.get("validUntil")) is int
            and manifest["validUntil"] > manifest["createdAt"],
            "candidate validity interval is invalid")
    require(isinstance(manifest.get("packages"), list) and manifest["packages"],
            "candidate package inventory must be non-empty")
    require(isinstance(manifest.get("files"), list),
            "candidate file inventory must be a list")
    expected = {MANIFEST}
    indexed = {}
    for entry in manifest["files"]:
        require(isinstance(entry, dict), "invalid candidate file entry")
        require(set(entry) == FILE_FIELDS, "invalid candidate file fields")
        path = entry.get("path")
        kind = classify(path, target)
        require(path not in expected and entry.get("kind") == kind,
                "duplicate file or incorrect inventory kind")
        require(type(entry.get("size")) is int and entry["size"] >= 0,
                "invalid inventory file size")
        require(isinstance(entry.get("sha256"), str) and REVISION.fullmatch(entry["sha256"]),
                "invalid inventory digest")
        candidate_file = root / path
        require(path in actual and candidate_file.stat().st_size == entry["size"]
                and digest(candidate_file) == entry["sha256"],
                "candidate file checksum or size differs")
        expected.add(path)
        indexed[path] = entry
        if path.startswith("repodata/") and kind == "immutable":
            require(Path(path).name.startswith(entry["sha256"] + "-"),
                    "repodata content filename and checksum differ")
    require(actual == expected, "candidate contains unlisted files")
    require("repodata/repomd.xml" in indexed and "repodata/repomd.xml.asc" in indexed,
            "candidate is missing signed repository metadata")
    require(f"keys/{fingerprint}.asc" in indexed,
            "candidate is missing its pinned public key")
    expected_package_fields = (PACKAGE_FIELDS | {"sourceRevision"}
                               if config["sourceRevision"] else PACKAGE_FIELDS)
    require(all(isinstance(item, dict) and set(item) == expected_package_fields
                for item in manifest["packages"]), "invalid package record fields")
    package_paths = {item.get("path") for item in manifest["packages"]}
    require(package_paths and all(package_path.fullmatch(path or "") for path in package_paths),
            "candidate has an invalid package record")
    require(len(package_paths) == len(manifest["packages"]),
            "candidate has duplicate package records")
    require(package_paths == {path for path in indexed if package_path.fullmatch(path)},
            "package records and file inventory differ")
    for package in manifest["packages"]:
        require(package["name"] == "loopwire"
                and package["release"] == config["packageRelease"]
                and package["architecture"] == "x86_64"
                and re.fullmatch(VERSION, package["version"])
                and package["path"] == (
                    f"packages/loopwire-{package['version']}-{config['packageRelease']}.x86_64.rpm"
                ), "candidate package identity is invalid")
        require(isinstance(package["sourceReleaseSha256"], str)
                and REVISION.fullmatch(package["sourceReleaseSha256"])
                and isinstance(package["distributedSha256"], str)
                and REVISION.fullmatch(package["distributedSha256"])
                and type(package["size"]) is int and package["size"] >= 0,
                "candidate package hash or size is invalid")
        if config["sourceRevision"]:
            require(isinstance(package["sourceRevision"], str)
                    and re.fullmatch(r"[0-9a-f]{40}", package["sourceRevision"]),
                    "candidate source revision is invalid")
        entry = indexed[package["path"]]
        require(entry["sha256"] == package["distributedSha256"]
                and entry["size"] == package["size"],
                "package record and file inventory differ")
    return manifest


def verify_signed(root, key, fingerprint, historical=False, target=DEFAULT_TARGET):
    manifest = inventory(root, fingerprint, target)
    verifier = Path(__file__).resolve().with_name("rpm-repository.py")
    require(verifier.is_file(), "rpm-repository.py verifier is missing")
    command = [sys.executable, str(verifier), "verify", "--repository", str(root),
               "--public-key", str(key), "--fingerprint", fingerprint]
    if target != DEFAULT_TARGET:
        command += ["--target", target]
    if historical:
        command += ["--now", str(manifest["createdAt"])]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    require(result.returncode == 0,
            "signed RPM repository verification failed; run rpm-repository.py verify for diagnostics")
    return manifest


def fsync_directory(path):
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fsync(descriptor)
    finally:
        os.close(descriptor)


def make_directory(path, mode=0o755):
    path = plain_path(path, directory=True, missing=True)
    if path.exists():
        return
    make_directory(path.parent, mode=mode)
    path.mkdir(mode=mode)
    descriptor = os.open(path, os.O_RDONLY | os.O_DIRECTORY | os.O_NOFOLLOW)
    try:
        os.fchmod(descriptor, mode)
        os.fsync(descriptor)
    finally:
        os.close(descriptor)
    fsync_directory(path.parent)


def atomic_write(target, source=None, data=None, mode=0o644, directory_mode=0o755):
    plain_path(target, missing=True)
    make_directory(target.parent, mode=directory_mode)
    descriptor, temporary = tempfile.mkstemp(prefix=".upload-", dir=target.parent)
    try:
        with os.fdopen(descriptor, "wb") as output:
            if source is not None:
                with source.open("rb") as incoming:
                    shutil.copyfileobj(incoming, output, 1024 * 1024)
            else:
                output.write(data)
            output.flush()
            os.fchmod(output.fileno(), mode)
            os.fsync(output.fileno())
        os.replace(temporary, target)
        fsync_directory(target.parent)
    finally:
        if os.path.exists(temporary):
            os.unlink(temporary)


def root_path(value):
    path = Path(value)
    require(path.is_absolute() and path != Path("/"),
            "--root must be an absolute, non-root directory")
    return plain_path(path, directory=True, missing=True)


def public_channel(root, target=DEFAULT_TARGET):
    _target, config, _package_path = target_config(target)
    return root / "public" / config["publicPrefix"]


def private_channel(root, target=DEFAULT_TARGET):
    target, _config, _package_path = target_config(target)
    return root if target == DEFAULT_TARGET else root / "channels" / target


@contextlib.contextmanager
def locked(root, create=False, target=DEFAULT_TARGET):
    target, _config, _package_path = target_config(target)
    private = private_channel(root, target)
    if create:
        make_directory(root)
        if target != DEFAULT_TARGET:
            make_directory(private.parent, mode=0o700)
            make_directory(private, mode=0o700)
    if not root.exists() or not private.exists():
        raise EmptyRepository("repository has no committed snapshot")
    lock = private / ".publish.lock"
    plain_path(lock, missing=True)
    if not create and not lock.exists():
        require(not (private / "state").exists() and not public_channel(root, target).exists(),
                "repository state exists without its publication lock")
        raise EmptyRepository("repository has no committed snapshot")
    flags = os.O_NOFOLLOW | (os.O_RDWR | os.O_CREAT if create else os.O_RDONLY)
    descriptor = os.open(lock, flags, 0o600)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                "invalid publication lock file")
        try:
            fcntl.flock(descriptor,
                        (fcntl.LOCK_EX if create else fcntl.LOCK_SH) | fcntl.LOCK_NB)
        except BlockingIOError:
            raise PublicationError("repository is locked by another operation; retry later") from None
        yield
    finally:
        os.close(descriptor)


def state(root, name, target=DEFAULT_TARGET):
    path = private_channel(root, target) / "state" / f"{name}.json"
    plain_path(path, missing=True)
    if not path.exists():
        return None
    information = path.stat()
    require(stat.S_ISREG(information.st_mode) and information.st_nlink == 1,
            "invalid publication state file")
    record = read_json(path)
    require(isinstance(record, dict) and isinstance(record.get("revision"), str)
            and REVISION.fullmatch(record["revision"]), "invalid publication state")
    if name == "current":
        require(set(record) == {"revision"}, "invalid current publication state")
    elif name == "pending":
        previous = record.get("previousRevision")
        require(set(record) == {"revision", "previousRevision"}
                and (previous == "empty" or isinstance(previous, str)
                     and REVISION.fullmatch(previous)),
                "invalid pending publication state")
    return record


def _checkpoint(label):
    """No-op hook for process-interruption tests; never environment-controlled."""


def check_public(root, manifest, immutable_only=False, target=DEFAULT_TARGET):
    channel = public_channel(root, target)
    for entry in manifest["files"]:
        if immutable_only and entry["kind"] != "immutable":
            continue
        public_file = channel / entry["path"]
        plain_path(public_file, missing=True)
        if public_file.exists():
            info = public_file.stat()
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                    "public target is not a standalone regular file")
            require(info.st_size == entry["size"] and digest(public_file) == entry["sha256"],
                    "immutable URL collision" if immutable_only
                    else "committed public repository has drifted")
        elif not immutable_only:
            raise PublicationError("committed public repository is missing files")
    if not immutable_only:
        public_manifest = channel / MANIFEST
        plain_path(public_manifest, missing=True)
        require(public_manifest.is_file() and public_manifest.stat().st_nlink == 1
                and read_json(public_manifest) == manifest,
                "committed public repository manifest has drifted")


def save_snapshot(root, repository, manifest, target=DEFAULT_TARGET):
    snapshots = private_channel(root, target) / "snapshots"
    make_directory(snapshots, mode=0o700)
    snapshot = snapshots / manifest["revision"]
    plain_path(snapshot, directory=True, missing=True)
    if snapshot.exists():
        require(inventory(snapshot, manifest["signingFingerprint"], target) == manifest,
                "retained snapshot differs from candidate")
        return snapshot
    temporary = Path(tempfile.mkdtemp(prefix=".staging-", dir=snapshots))
    try:
        os.chmod(temporary, 0o700)
        for entry in manifest["files"]:
            atomic_write(temporary / entry["path"], source=repository / entry["path"],
                         mode=0o600, directory_mode=0o700)
        atomic_write(temporary / MANIFEST, source=repository / MANIFEST,
                     mode=0o600, directory_mode=0o700)
        inventory(temporary, manifest["signingFingerprint"], target)
        fsync_directory(temporary)
        os.replace(temporary, snapshot)
        fsync_directory(snapshots)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return snapshot


def promote(root, snapshot, manifest, target=DEFAULT_TARGET):
    """Publish immutable data, signature, then atomic repomd.xml commit."""
    private = private_channel(root, target)
    channel = public_channel(root, target)
    make_directory(channel)
    devices = {path.stat().st_dev for path in
               (root, channel, private / "state", private / "snapshots")}
    require(len(devices) == 1,
            "origin public, snapshot, and state paths must share one filesystem")
    check_public(root, manifest, immutable_only=True, target=target)
    for entry in manifest["files"]:
        if entry["kind"] == "immutable":
            public_file = channel / entry["path"]
            if not public_file.exists():
                atomic_write(public_file, source=snapshot / entry["path"])
    _checkpoint("immutable")
    signature = "repodata/repomd.xml.asc"
    atomic_write(channel / signature, source=snapshot / signature)
    _checkpoint("signature")
    metadata = "repodata/repomd.xml"
    atomic_write(channel / metadata, source=snapshot / metadata)
    _checkpoint("committed")
    atomic_write(channel / MANIFEST, source=snapshot / MANIFEST)
    check_public(root, manifest, target=target)
    _checkpoint("manifest")
    atomic_write(private / "state" / "current.json",
                 data=canonical({"revision": manifest["revision"]}) + b"\n", mode=0o600)
    _checkpoint("current")
    (private / "state" / "pending.json").unlink()
    fsync_directory(private / "state")
    _target, config, _package_path = target_config(target)
    return {"status": "published", "revision": manifest["revision"],
            "target": config["manifest"].copy()}


def publish_at(root, repository, fingerprint, expected, target=DEFAULT_TARGET):
    target, config, _package_path = target_config(target)
    private = private_channel(root, target)
    manifest = inventory(repository, fingerprint, target)
    with locked(root, create=True, target=target):
        current = state(root, "current", target)
        pending = state(root, "pending", target)
        revision = current["revision"] if current else "empty"
        if pending:
            require(pending["revision"] == manifest["revision"],
                    "interrupted publication pending; recover it before publishing another revision")
            require(expected == pending.get("previousRevision"),
                    "expected revision differs from interrupted publication")
            require(revision in (pending["previousRevision"], pending["revision"]),
                    "current revision conflicts with pending journal")
            snapshot = private / "snapshots" / pending["revision"]
            require(inventory(snapshot, fingerprint, target) == manifest,
                    "pending snapshot differs from candidate")
            return promote(root, snapshot, manifest, target)
        if revision == manifest["revision"]:
            check_public(root, manifest, target=target)
            return {"status": "unchanged", "revision": revision,
                    "target": config["manifest"].copy()}
        require(expected == revision,
                "expected revision differs from current publication (compare-and-swap failed)")
        if current is None:
            channel = public_channel(root, target)
            plain_path(channel, directory=True, missing=True)
            require(not channel.exists() or not any(channel.iterdir()),
                    "refusing to adopt an unmanaged public RPM repository")
        check_public(root, manifest, immutable_only=True, target=target)
        snapshot = save_snapshot(root, repository, manifest, target)
        make_directory(private / "state", mode=0o700)
        atomic_write(private / "state" / "pending.json", data=canonical({
            "revision": manifest["revision"], "previousRevision": revision,
        }) + b"\n", mode=0o600)
        _checkpoint("journal")
        return promote(root, snapshot, manifest, target)


def recover_at(root, fingerprint, revision, target=DEFAULT_TARGET):
    private = private_channel(root, target)
    with locked(root, create=True, target=target):
        pending = state(root, "pending", target)
        require(pending is not None and pending["revision"] == revision,
                "pending publication changed; fetch and verify it again before recovery")
        current = state(root, "current", target)
        require((current["revision"] if current else "empty")
                in (pending.get("previousRevision"), revision),
                "current revision conflicts with pending journal")
        snapshot = private / "snapshots" / revision
        return promote(root, snapshot, inventory(snapshot, fingerprint, target), target)


@contextlib.contextmanager
def selected_snapshot(root, fingerprint, revision=None, pending_only=False,
                      target=DEFAULT_TARGET):
    private = private_channel(root, target)
    with locked(root, target=target):
        pending = state(root, "pending", target)
        if pending_only:
            if not pending:
                raise EmptyRepository("repository has no pending publication")
            revision = pending["revision"]
        else:
            require(pending is None,
                    "interrupted publication pending; recover before fetching snapshots")
            if revision is None:
                current = state(root, "current", target)
                if not current:
                    raise EmptyRepository("repository has no committed snapshot")
                revision = current["revision"]
        snapshot = private / "snapshots" / revision
        manifest = inventory(snapshot, fingerprint, target)
        require(manifest["revision"] == revision,
                "snapshot does not match selected revision")
        yield snapshot, manifest


def write_archive(repository, output):
    with tarfile.open(fileobj=output, mode="w|") as archive:
        for relative in sorted(tree_files(repository)):
            archive.add(repository / relative, arcname=relative, recursive=False)


def read_archive(source, output, target=DEFAULT_TARGET):
    seen = set()
    with tarfile.open(fileobj=source, mode="r|*") as archive:
        for member in archive:
            safe_path(member.name)
            require(member.name == MANIFEST or classify(member.name, target),
                    "unexpected archive path")
            require(member.isfile() and not member.issym() and not member.islnk()
                    and member.name not in seen,
                    "archive contains a link, special file, or duplicate")
            seen.add(member.name)
            destination_file = output / member.name
            make_directory(destination_file.parent)
            with archive.extractfile(member) as incoming, destination_file.open("xb") as destination:
                shutil.copyfileobj(incoming, destination, 1024 * 1024)


def ssh_command(args, request):
    require(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*", args.ssh),
            "--ssh must be USER@HOST using a hostname or IPv4 address")
    require(args.known_hosts is not None and args.identity_file is not None,
            "remote operations require --known-hosts and --identity-file")
    known_hosts = plain_path(args.known_hosts)
    identity = plain_path(args.identity_file)
    require(known_hosts.is_file() and known_hosts.stat().st_nlink == 1,
            "--known-hosts must name a regular file")
    require(identity.is_file() and identity.stat().st_nlink == 1,
            "--identity-file must name a regular file")
    command = ["ssh", "-F", "/dev/null", "-T", "-o", "BatchMode=yes",
               "-o", "StrictHostKeyChecking=yes",
               "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
               "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes",
               "-o", "ConnectTimeout=15", "-o", f"UserKnownHostsFile={known_hosts}",
               "-o", "GlobalKnownHostsFile=/dev/null", "-i", str(identity),
               "-o", "IdentitiesOnly=yes"]
    if args.ssh_port:
        command += ["-p", str(args.ssh_port)]
    encoded = base64.urlsafe_b64encode(canonical(request)).decode("ascii")
    source = Path(__file__).read_text(encoding="utf-8")
    remote = "python3 -c " + shlex.quote(source) + " _serve " + shlex.quote(encoded)
    return command + ["--", args.ssh, remote]


def remote_call(args, request, repository=None, output=None):
    command = ssh_command(args, request)
    with tempfile.TemporaryFile() as incoming, tempfile.TemporaryFile() as outgoing:
        if repository:
            write_archive(repository, incoming)
            incoming.seek(0)
        result = subprocess.run(command, stdin=incoming, stdout=outgoing,
                                stderr=subprocess.PIPE, check=False)
        if result.returncode == 3:
            raise EmptyRepository("remote repository has no selected snapshot")
        if result.returncode == 1:
            try:
                failure = json.loads(result.stderr)
                if failure.get("status") == "error" and isinstance(failure.get("message"), str):
                    raise PublicationError(failure["message"])
            except (ValueError, AttributeError):
                pass
        require(result.returncode == 0,
                "SSH repository operation failed; check pinned host key, identity, connectivity, remote Python, and publisher state")
        outgoing.seek(0)
        if output:
            read_archive(outgoing, output, request.get("target", DEFAULT_TARGET))
            return None
        try:
            return json.load(outgoing)
        except (ValueError, UnicodeError) as error:
            raise PublicationError("SSH repository response is not valid JSON") from error


def serve(request):
    root = root_path(request["root"])
    target, _config, _package_path = target_config(
        request.get("target", DEFAULT_TARGET)
    )
    fingerprint = request["fingerprint"]
    require(FINGERPRINT.fullmatch(fingerprint), "invalid signing fingerprint")
    action = request["action"]
    if action == "publish":
        require(request["expected"] == "empty" or REVISION.fullmatch(request["expected"]),
                "invalid expected revision")
        with tempfile.TemporaryDirectory(prefix="loopwire-rpm-upload-") as directory:
            repository = Path(directory)
            read_archive(sys.stdin.buffer, repository, target)
            return publish_at(root, repository, fingerprint, request["expected"], target)
    if action == "recover":
        require(REVISION.fullmatch(request["revision"]), "invalid recovery revision")
        return recover_at(root, fingerprint, request["revision"], target)
    require(action in ("fetch", "fetch-pending"), "unknown remote operation")
    revision = request.get("revision")
    require(revision is None or REVISION.fullmatch(revision), "invalid fetch revision")
    with selected_snapshot(root, fingerprint, revision,
                           action == "fetch-pending", target) as (snapshot, _):
        write_archive(snapshot, sys.stdout.buffer)
    return None


def fetch_into(args, output, pending_only=False):
    target = getattr(args, "target", DEFAULT_TARGET)
    if args.ssh:
        remote_call(args, {
            "action": "fetch-pending" if pending_only else "fetch",
            "root": args.root,
            "target": target,
            "fingerprint": args.fingerprint,
            "revision": getattr(args, "revision", None),
        }, output=output)
    else:
        with selected_snapshot(root_path(args.root), args.fingerprint,
                               getattr(args, "revision", None),
                               pending_only, target) as (snapshot, _):
            shutil.copytree(snapshot, output, dirs_exist_ok=True)
    historical = not pending_only or getattr(args, "allow_expired", False)
    return verify_signed(output, args.public_key, args.fingerprint,
                         historical=historical, target=target)


def parser():
    result = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    actions = result.add_subparsers(dest="action", required=True)
    for name in ("publish", "fetch", "recover"):
        action = actions.add_parser(name)
        action.add_argument("--root", required=True,
                            help="absolute origin root; HTTP serves ROOT/public")
        action.add_argument("--public-key", required=True, type=Path)
        action.add_argument("--fingerprint", required=True)
        action.add_argument("--target", choices=tuple(TARGETS), default=DEFAULT_TARGET,
                            help="isolated repository target (defaults to Fedora 44 x86_64)")
        action.add_argument("--ssh", metavar="USER@HOST",
                            help="omit for a local POSIX origin")
        action.add_argument("--ssh-port", type=int)
        action.add_argument("--identity-file", type=Path,
                            help="required SSH private identity for remote operations")
        action.add_argument("--known-hosts", type=Path,
                            help="required pinned known_hosts for remote operations")
        if name == "publish":
            action.add_argument("--repository", type=Path, required=True)
            action.add_argument("--expected-revision", required=True,
                                help="observed revision, or literal empty for first publication")
            action.add_argument("--dry-run", action="store_true",
                                help="verify locally; perform no origin access or upload")
        elif name == "fetch":
            action.add_argument("--output", type=Path, required=True,
                                help="new destination directory (must not exist)")
            action.add_argument("--revision",
                                help="retained snapshot revision; defaults to committed current")
        else:
            action.add_argument("--dry-run", action="store_true",
                                help="fetch and verify pending snapshot without promotion")
            action.add_argument("--allow-expired", action="store_true",
                                help="finish an expired signed journal, then immediately publish fresh metadata")
    return result


def run(args):
    target, config, _package_path = target_config(
        getattr(args, "target", DEFAULT_TARGET)
    )
    if args.ssh:
        requested_root = Path(args.root)
        require(requested_root.is_absolute() and args.root != "/"
                and ".." not in requested_root.parts
                and requested_root.as_posix() == args.root,
                "--root must be an absolute normalized non-root path")
    else:
        root_path(args.root)
    require(FINGERPRINT.fullmatch(args.fingerprint),
            "--fingerprint must be a full uppercase fingerprint")
    require(args.ssh_port is None or 1 <= args.ssh_port <= 65535,
            "invalid SSH port")
    require(args.ssh or (args.ssh_port is None and args.known_hosts is None
                         and args.identity_file is None),
            "SSH options require --ssh")
    if args.ssh:
        require(args.known_hosts is not None and args.identity_file is not None,
                "remote operations require --known-hosts and --identity-file")
    args.public_key = plain_path(args.public_key)
    require(args.public_key.is_file() and args.public_key.stat().st_nlink == 1,
            "--public-key must name a regular file")
    if args.action == "publish":
        require(args.expected_revision == "empty" or REVISION.fullmatch(args.expected_revision),
                "invalid expected revision")
        manifest = verify_signed(args.repository, args.public_key, args.fingerprint,
                                 target=target)
        if args.dry_run:
            return {"status": "validated", "revision": manifest["revision"],
                    "originChecked": False}
        with tempfile.TemporaryDirectory(prefix="loopwire-rpm-candidate-") as directory:
            candidate = Path(directory) / "repository"
            shutil.copytree(args.repository, candidate, symlinks=True)
            require(verify_signed(candidate, args.public_key, args.fingerprint,
                                  target=target) == manifest,
                    "candidate changed during verification")
            if args.ssh:
                return remote_call(args, {
                    "action": "publish", "root": args.root,
                    "target": target,
                    "fingerprint": args.fingerprint,
                    "expected": args.expected_revision,
                }, repository=candidate)
            return publish_at(root_path(args.root), candidate, args.fingerprint,
                              args.expected_revision, target)
    if args.action == "fetch":
        require(args.revision is None or REVISION.fullmatch(args.revision),
                "invalid selected revision")
        output = plain_path(args.output, directory=True, missing=True)
        require(not output.exists(), "--output must not exist")
        require(output.parent.is_dir(), "--output parent must already exist")
        with tempfile.TemporaryDirectory(prefix=".loopwire-rpm-fetch-",
                                         dir=output.parent) as directory:
            fetched = Path(directory) / "repository"
            fetched.mkdir()
            manifest = fetch_into(args, fetched)
            os.rename(fetched, output)
            fsync_directory(output.parent)
        return {"status": "fetched", "revision": manifest["revision"]}
    with tempfile.TemporaryDirectory(prefix="loopwire-rpm-recovery-") as directory:
        manifest = fetch_into(args, Path(directory), pending_only=True)
        needs_refresh = manifest["validUntil"] <= int(time.time())
        if args.dry_run:
            return {"status": "recovery-validated", "revision": manifest["revision"],
                    "requiresRefresh": needs_refresh}
        if args.ssh:
            result = remote_call(args, {
                "action": "recover", "root": args.root,
                "target": target,
                "fingerprint": args.fingerprint, "revision": manifest["revision"],
            })
        else:
            result = recover_at(root_path(args.root), args.fingerprint,
                                manifest["revision"], target)
        result["requiresRefresh"] = needs_refresh
        if needs_refresh:
            result["nextAction"] = (
                "Immediately fetch, rebuild, sign, and publish fresh metadata; "
                f"the project verifier rejects the expired snapshot. {config['client']} "
                "signature checks do not enforce this project deadline."
            )
        return result


def main():
    try:
        if len(sys.argv) == 3 and sys.argv[1] == "_serve":
            result = serve(json.loads(base64.urlsafe_b64decode(sys.argv[2])))
        else:
            result = run(parser().parse_args())
        if result is not None:
            print(json.dumps(result, sort_keys=True))
        return 0
    except EmptyRepository:
        print(json.dumps({"status": "empty", "revision": None}))
        return 3
    except (PublicationError, OSError, ValueError, KeyError, TypeError,
            tarfile.TarError) as error:
        message = (str(error) if isinstance(error, PublicationError)
                   else "repository operation failed; check filesystem and inputs")
        print(json.dumps({"status": "error", "message": message}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
