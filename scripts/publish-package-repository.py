#!/usr/bin/env python3
"""Publish verified APT trees to a POSIX origin; no third-party Python modules.

ROOT/public is the HTTP document root. ROOT/snapshots and ROOT/state are private.
Snapshots and pool/by-hash URLs are retained indefinitely. Each suite's InRelease
is an independent atomic commit point, not a transaction across suites. The
durable pending journal must be completed before any competing publication.

The SSH transport runs this same source with Python on the origin. All arguments
are encoded data, host keys must already be trusted, and no credentials are sent
in arguments or output. Signature verification happens on the client; the
authenticated transport and origin independently check the full file inventory.
The origin needs Python 3, SSH, and a dedicated account with exclusive ownership
of ROOT on a filesystem implementing flock, fsync, and same-directory rename.
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


SUITES = ("debian-13", "ubuntu-24.04")
MANIFEST = "repository-manifest.json"
REVISION = re.compile(r"[0-9a-f]{64}\Z")
FINGERPRINT = re.compile(r"(?:[A-F0-9]{40}|[A-F0-9]{64})\Z")


class PublicationError(Exception):
    """An actionable publication failure, with no private transport details."""


class EmptyRepository(PublicationError):
    """No committed snapshot exists (distinct exit status 3)."""


def require(condition, message):
    if not condition:
        raise PublicationError(message)


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def digest(path):
    with path.open("rb") as source:
        return hashlib.file_digest(source, "sha256").hexdigest() if hasattr(hashlib, "file_digest") else _digest_stream(source)


def _digest_stream(source):
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


def classify(path):
    """Derive ownership from the protocol, never from an arbitrary manifest kind."""
    safe_path(path)
    if re.fullmatch(r"pool/(ubuntu-24\.04|debian-13)/main/l/loopwire/[A-Za-z0-9][A-Za-z0-9.+_~-]*\.deb", path):
        return "immutable"
    if re.fullmatch(r"keys/(?:[A-F0-9]{40}|[A-F0-9]{64})\.asc", path):
        return "immutable"
    if re.fullmatch(r"dists/(ubuntu-24\.04|debian-13)/main/binary-amd64/by-hash/SHA256/[0-9a-f]{64}", path):
        return "immutable"
    if re.fullmatch(r"dists/(ubuntu-24\.04|debian-13)/(InRelease|Release|main/binary-amd64/Packages(?:\.gz)?)", path):
        return "metadata"
    raise PublicationError("inventory contains a path outside the APT protocol")


def plain_path(path, directory=False, missing=False):
    """Reject symlinks in every ancestor, including deployment/output roots."""
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
    plain_path(root, directory=True)
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


def inventory(root, fingerprint):
    root = plain_path(root, directory=True)
    actual = tree_files(root)
    require(MANIFEST in actual, "candidate is missing its manifest")
    manifest = read_json(root / MANIFEST)
    require(isinstance(manifest, dict) and manifest.get("schemaVersion") == 1,
            "unsupported repository manifest")
    revision = manifest.get("revision")
    require(isinstance(revision, str) and REVISION.fullmatch(revision), "invalid candidate revision")
    unsigned = {key: value for key, value in manifest.items() if key != "revision"}
    require(hashlib.sha256(canonical(unsigned)).hexdigest() == revision,
            "candidate revision does not match its manifest")
    require(manifest.get("signingFingerprint") == fingerprint, "candidate signing fingerprint differs")
    require(isinstance(manifest.get("files"), list), "candidate inventory must be a list")
    expected = {MANIFEST}
    for entry in manifest["files"]:
        require(isinstance(entry, dict), "invalid candidate file entry")
        path = entry.get("path")
        kind = classify(path)
        require(path not in expected and entry.get("kind") == kind,
                "duplicate file or incorrect inventory kind")
        require(type(entry.get("size")) is int and entry["size"] >= 0,
                "invalid inventory file size")
        require(isinstance(entry.get("sha256"), str) and REVISION.fullmatch(entry["sha256"]),
                "invalid inventory digest")
        target = root / path
        require(path in actual and target.stat().st_size == entry["size"]
                and digest(target) == entry["sha256"], "candidate file checksum or size differs")
        expected.add(path)
    require(actual == expected, "candidate contains unlisted files")
    require({suite.get("name") for suite in manifest.get("suites", [])} == set(SUITES),
            "candidate must contain both supported suites")
    for suite in SUITES:
        for suffix in ("Release", "InRelease", "main/binary-amd64/Packages", "main/binary-amd64/Packages.gz"):
            require(f"dists/{suite}/{suffix}" in expected, "candidate is missing required suite metadata")
    require(f"keys/{fingerprint}.asc" in expected, "candidate is missing its public key")
    return manifest


def verify_signed(root, key, fingerprint, historical=False):
    manifest = inventory(root, fingerprint)
    verifier = Path(__file__).resolve().with_name("apt-repository.py")
    require(verifier.is_file(), "apt-repository.py verifier is missing")
    command = [sys.executable, str(verifier), "verify", "--repository", str(root),
               "--public-key", str(key), "--fingerprint", fingerprint]
    if historical:
        require(type(manifest.get("createdAt")) is int, "invalid repository creation time")
        command += ["--now", str(manifest["createdAt"])]
    result = subprocess.run(command, capture_output=True, text=True, check=False)
    require(result.returncode == 0, "signed repository verification failed; run apt-repository.py verify for diagnostics")
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
        # mkdir applies the SSH/workflow umask; set our intended mode only on
        # newly created directories, preserving operator-provisioned ancestors.
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


def read_json(path):
    plain_path(path)
    try:
        with path.open(encoding="utf-8") as source:
            return json.load(source)
    except (ValueError, UnicodeError) as error:
        raise PublicationError("invalid repository JSON") from error


def root_path(value):
    path = Path(value)
    require(path.is_absolute() and path != Path("/"), "--root must be an absolute, non-root directory")
    return plain_path(path, directory=True, missing=True)


@contextlib.contextmanager
def locked(root, create=False):
    if create:
        make_directory(root)
    if not root.exists():
        raise EmptyRepository("repository has no committed snapshot")
    lock = root / ".publish.lock"
    plain_path(lock, missing=True)
    if not create and not lock.exists():
        require(not (root / "state").exists() and not (root / "public").exists(),
                "repository state exists without its publication lock")
        raise EmptyRepository("repository has no committed snapshot")
    descriptor = os.open(lock, os.O_NOFOLLOW | (os.O_RDWR | os.O_CREAT if create else os.O_RDONLY), 0o600)
    try:
        info = os.fstat(descriptor)
        require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1, "invalid publication lock file")
        try:
            fcntl.flock(descriptor, (fcntl.LOCK_EX if create else fcntl.LOCK_SH) | fcntl.LOCK_NB)
        except BlockingIOError:
            raise PublicationError("repository is locked by another operation; retry later") from None
        yield
    finally:
        os.close(descriptor)


def state(root, name):
    path = root / "state" / f"{name}.json"
    plain_path(path, missing=True)
    if not path.exists():
        return None
    record = read_json(path)
    require(isinstance(record, dict) and isinstance(record.get("revision"), str)
            and REVISION.fullmatch(record["revision"]), "invalid publication state")
    return record


def _checkpoint(label):
    """No-op hook for process-interruption tests; never controlled by environment."""


def check_public(root, manifest, immutable_only=False):
    for entry in manifest["files"]:
        if immutable_only and entry["kind"] != "immutable":
            continue
        target = root / "public" / entry["path"]
        plain_path(target, missing=True)
        if target.exists():
            info = target.stat()
            require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
                    "public target is not a standalone regular file")
            require(info.st_size == entry["size"] and digest(target) == entry["sha256"],
                    "immutable URL collision" if immutable_only else "committed public repository has drifted")
        elif not immutable_only:
            raise PublicationError("committed public repository is missing files")


def save_snapshot(root, repository, manifest):
    snapshots = root / "snapshots"
    make_directory(snapshots, mode=0o700)
    snapshot = snapshots / manifest["revision"]
    plain_path(snapshot, directory=True, missing=True)
    if snapshot.exists():
        require(inventory(snapshot, manifest["signingFingerprint"]) == manifest,
                "retained snapshot differs from candidate")
        return snapshot
    temporary = Path(tempfile.mkdtemp(prefix=".staging-", dir=snapshots))
    try:
        for entry in manifest["files"]:
            atomic_write(temporary / entry["path"], source=repository / entry["path"],
                         mode=0o600, directory_mode=0o700)
        atomic_write(temporary / MANIFEST, source=repository / MANIFEST, mode=0o600, directory_mode=0o700)
        inventory(temporary, manifest["signingFingerprint"])
        fsync_directory(temporary)
        os.replace(temporary, snapshot)
        fsync_directory(snapshots)
    finally:
        if temporary.exists():
            shutil.rmtree(temporary)
    return snapshot


def promote(root, snapshot, manifest):
    """Resumable order: all immutable objects, metadata, per-suite InRelease."""
    check_public(root, manifest, immutable_only=True)
    for entry in manifest["files"]:
        if entry["kind"] == "immutable":
            target = root / "public" / entry["path"]
            if not target.exists():
                atomic_write(target, source=snapshot / entry["path"])
    _checkpoint("immutable")
    for suite in SUITES:
        prefix = f"dists/{suite}/"
        for entry in manifest["files"]:
            if entry["kind"] == "metadata" and entry["path"].startswith(prefix) and not entry["path"].endswith("/InRelease"):
                atomic_write(root / "public" / entry["path"], source=snapshot / entry["path"])
        _checkpoint("metadata:" + suite)
        relative = f"dists/{suite}/InRelease"
        atomic_write(root / "public" / relative, source=snapshot / relative)
        _checkpoint("committed:" + suite)
    atomic_write(root / "public" / MANIFEST, source=snapshot / MANIFEST)
    check_public(root, manifest)
    atomic_write(root / "state" / "current.json", data=canonical({"revision": manifest["revision"]}) + b"\n", mode=0o600)
    _checkpoint("current")
    (root / "state" / "pending.json").unlink()
    fsync_directory(root / "state")
    return {"status": "published", "revision": manifest["revision"], "suites": list(SUITES)}


def publish_at(root, repository, fingerprint, expected):
    manifest = inventory(repository, fingerprint)
    with locked(root, create=True):
        current = state(root, "current")
        pending = state(root, "pending")
        revision = current["revision"] if current else "empty"
        if pending:
            require(pending["revision"] == manifest["revision"],
                    "interrupted publication pending; recover it before publishing another revision")
            require(expected == pending.get("previousRevision"), "expected revision differs from interrupted publication")
            require(revision in (pending["previousRevision"], pending["revision"]), "current revision conflicts with pending journal")
            snapshot = root / "snapshots" / pending["revision"]
            require(inventory(snapshot, fingerprint) == manifest, "pending snapshot differs from candidate")
            return promote(root, snapshot, manifest)
        if revision == manifest["revision"]:
            check_public(root, manifest)
            return {"status": "unchanged", "revision": revision, "suites": list(SUITES)}
        require(expected == revision, "expected revision differs from current publication (compare-and-swap failed)")
        if current is None:
            public = root / "public"
            plain_path(public, directory=True, missing=True)
            require(not public.exists() or not any(public.iterdir()), "refusing to adopt an unmanaged public repository")
        check_public(root, manifest, immutable_only=True)
        snapshot = save_snapshot(root, repository, manifest)
        make_directory(root / "state", mode=0o700)
        atomic_write(root / "state" / "pending.json", data=canonical({
            "revision": manifest["revision"], "previousRevision": revision,
        }) + b"\n", mode=0o600)
        _checkpoint("journal")
        return promote(root, snapshot, manifest)


def recover_at(root, fingerprint, revision):
    with locked(root, create=True):
        pending = state(root, "pending")
        require(pending is not None and pending["revision"] == revision,
                "pending publication changed; fetch and verify it again before recovery")
        current = state(root, "current")
        require((current["revision"] if current else "empty") in (pending.get("previousRevision"), revision),
                "current revision conflicts with pending journal")
        snapshot = root / "snapshots" / revision
        return promote(root, snapshot, inventory(snapshot, fingerprint))


@contextlib.contextmanager
def selected_snapshot(root, fingerprint, revision=None, pending_only=False):
    with locked(root):
        pending = state(root, "pending")
        if pending_only:
            if not pending:
                raise EmptyRepository("repository has no pending publication")
            revision = pending["revision"]
        else:
            require(pending is None, "interrupted publication pending; recover before fetching snapshots")
            if revision is None:
                current = state(root, "current")
                if not current:
                    raise EmptyRepository("repository has no committed snapshot")
                revision = current["revision"]
        snapshot = root / "snapshots" / revision
        manifest = inventory(snapshot, fingerprint)
        require(manifest["revision"] == revision, "snapshot does not match selected revision")
        yield snapshot, manifest


def write_archive(repository, output):
    with tarfile.open(fileobj=output, mode="w|") as archive:
        for relative in sorted(tree_files(repository)):
            archive.add(repository / relative, arcname=relative, recursive=False)


def read_archive(source, output):
    seen = set()
    with tarfile.open(fileobj=source, mode="r|*") as archive:
        for member in archive:
            safe_path(member.name)
            require(member.name == MANIFEST or classify(member.name), "unexpected archive path")
            require(member.isfile() and not member.issym() and not member.islnk()
                    and member.name not in seen, "archive contains a link, special file, or duplicate")
            seen.add(member.name)
            target = output / member.name
            make_directory(target.parent)
            with archive.extractfile(member) as incoming, target.open("xb") as destination:
                shutil.copyfileobj(incoming, destination, 1024 * 1024)


def ssh_command(args, request):
    require(re.fullmatch(r"[A-Za-z0-9_][A-Za-z0-9_.-]*@[A-Za-z0-9][A-Za-z0-9_.-]*", args.ssh),
            "--ssh must be USER@HOST using an SSH alias, hostname, or IPv4 address")
    command = ["ssh", "-T", "-o", "BatchMode=yes", "-o", "StrictHostKeyChecking=yes",
               "-o", "PasswordAuthentication=no", "-o", "KbdInteractiveAuthentication=no",
               "-o", "ForwardAgent=no", "-o", "ClearAllForwardings=yes", "-o", "ConnectTimeout=15"]
    if args.known_hosts:
        key_file = plain_path(args.known_hosts)
        require(key_file.is_file(), "--known-hosts must name a regular file")
        command += ["-o", f"UserKnownHostsFile={key_file}"]
    if args.ssh_port:
        command += ["-p", str(args.ssh_port)]
    if args.identity_file:
        identity = plain_path(args.identity_file)
        require(identity.is_file(), "--identity-file must name a regular file")
        command += ["-i", str(identity), "-o", "IdentitiesOnly=yes"]
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
        result = subprocess.run(command, stdin=incoming, stdout=outgoing, stderr=subprocess.PIPE, check=False)
        if result.returncode == 3:
            raise EmptyRepository("remote repository has no selected snapshot")
        if result.returncode == 1:
            # Forward only the server's deliberately sanitized structured error.
            # SSH diagnostics can contain hostnames/paths and stay private.
            try:
                failure = json.loads(result.stderr)
                if failure.get("status") == "error" and isinstance(failure.get("message"), str):
                    raise PublicationError(failure["message"])
            except (ValueError, AttributeError):
                pass
        require(result.returncode == 0,
                "SSH repository operation failed; check trusted host keys, connectivity, remote Python, and publisher state")
        outgoing.seek(0)
        if output:
            read_archive(outgoing, output)
            return None
        try:
            return json.load(outgoing)
        except (ValueError, UnicodeError) as error:
            raise PublicationError("SSH repository response is not valid JSON") from error


def serve(request):
    root = root_path(request["root"])
    fingerprint = request["fingerprint"]
    require(FINGERPRINT.fullmatch(fingerprint), "invalid signing fingerprint")
    action = request["action"]
    if action == "publish":
        require(request["expected"] == "empty" or REVISION.fullmatch(request["expected"]), "invalid expected revision")
        with tempfile.TemporaryDirectory(prefix="loopwire-apt-upload-") as directory:
            repository = Path(directory)
            read_archive(sys.stdin.buffer, repository)
            return publish_at(root, repository, fingerprint, request["expected"])
    if action == "recover":
        require(REVISION.fullmatch(request["revision"]), "invalid recovery revision")
        return recover_at(root, fingerprint, request["revision"])
    require(action in ("fetch", "fetch-pending"), "unknown remote operation")
    revision = request.get("revision")
    require(revision is None or REVISION.fullmatch(revision), "invalid fetch revision")
    with selected_snapshot(root, fingerprint, revision, action == "fetch-pending") as (snapshot, _):
        write_archive(snapshot, sys.stdout.buffer)
    return None


def fetch_into(args, output, pending_only=False):
    if args.ssh:
        remote_call(args, {"action": "fetch-pending" if pending_only else "fetch", "root": args.root,
                          "fingerprint": args.fingerprint, "revision": getattr(args, "revision", None)}, output=output)
    else:
        with selected_snapshot(root_path(args.root), args.fingerprint,
                               getattr(args, "revision", None), pending_only) as (snapshot, _):
            shutil.copytree(snapshot, output, dirs_exist_ok=True)
    return verify_signed(output, args.public_key, args.fingerprint,
                         historical=not pending_only or getattr(args, "allow_expired", False))


def parser():
    result = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    actions = result.add_subparsers(dest="action", required=True)
    for name in ("publish", "fetch", "recover"):
        action = actions.add_parser(name)
        action.add_argument("--root", required=True, help="absolute origin root; HTTP serves ROOT/public")
        action.add_argument("--public-key", required=True, type=Path)
        action.add_argument("--fingerprint", required=True)
        action.add_argument("--ssh", metavar="USER@HOST", help="omit for a local POSIX origin")
        action.add_argument("--ssh-port", type=int)
        action.add_argument("--identity-file", type=Path, help="existing SSH private key; alternatively use the caller's agent")
        action.add_argument("--known-hosts", type=Path, help="pre-provisioned known_hosts; strict checking is mandatory")
        if name == "publish":
            action.add_argument("--repository", type=Path, required=True)
            action.add_argument("--expected-revision", required=True, help="observed revision, or literal empty for first publication")
            action.add_argument("--dry-run", action="store_true", help="verify locally; perform no origin access or upload")
        elif name == "fetch":
            action.add_argument("--output", type=Path, required=True, help="new destination directory (must not exist)")
            action.add_argument("--revision", help="retained snapshot revision; defaults to committed current")
        else:
            action.add_argument("--dry-run", action="store_true", help="fetch and verify pending snapshot without promotion")
            action.add_argument("--allow-expired", action="store_true",
                                help="finish an expired signed journal, then immediately fetch, re-sign, and publish fresh metadata")
    return result


def run(args):
    root_path(args.root) if not args.ssh else require(Path(args.root).is_absolute() and args.root != "/"
                                                     and ".." not in Path(args.root).parts,
                                                     "--root must be an absolute normalized non-root path")
    require(FINGERPRINT.fullmatch(args.fingerprint), "--fingerprint must be a full uppercase fingerprint")
    require(args.ssh_port is None or 1 <= args.ssh_port <= 65535, "invalid SSH port")
    require(args.ssh or (args.ssh_port is None and args.known_hosts is None and args.identity_file is None),
            "SSH options require --ssh")
    args.public_key = plain_path(args.public_key)
    require(args.public_key.is_file(), "--public-key must name a file")
    if args.action == "publish":
        require(args.expected_revision == "empty" or REVISION.fullmatch(args.expected_revision), "invalid expected revision")
        manifest = verify_signed(args.repository, args.public_key, args.fingerprint)
        if args.dry_run:
            return {"status": "validated", "revision": manifest["revision"], "originChecked": False}
        with tempfile.TemporaryDirectory(prefix="loopwire-apt-candidate-") as directory:
            candidate = Path(directory) / "repository"
            shutil.copytree(args.repository, candidate, symlinks=True)
            require(verify_signed(candidate, args.public_key, args.fingerprint) == manifest,
                    "candidate changed during verification")
            if args.ssh:
                return remote_call(args, {"action": "publish", "root": args.root, "fingerprint": args.fingerprint,
                                          "expected": args.expected_revision}, repository=candidate)
            return publish_at(root_path(args.root), candidate, args.fingerprint, args.expected_revision)
    if args.action == "fetch":
        require(args.revision is None or REVISION.fullmatch(args.revision), "invalid selected revision")
        output = plain_path(args.output, directory=True, missing=True)
        require(not output.exists(), "--output must not exist")
        require(output.parent.is_dir(), "--output parent must already exist")
        with tempfile.TemporaryDirectory(prefix=".loopwire-apt-fetch-", dir=output.parent) as directory:
            fetched = Path(directory) / "repository"
            fetched.mkdir()
            manifest = fetch_into(args, fetched)
            os.rename(fetched, output)
            fsync_directory(output.parent)
        return {"status": "fetched", "revision": manifest["revision"]}
    with tempfile.TemporaryDirectory(prefix="loopwire-apt-recovery-") as directory:
        manifest = fetch_into(args, Path(directory), pending_only=True)
        needs_refresh = manifest["validUntil"] <= int(time.time())
        if args.dry_run:
            return {"status": "recovery-validated", "revision": manifest["revision"], "requiresRefresh": needs_refresh}
        if args.ssh:
            result = remote_call(args, {"action": "recover", "root": args.root, "fingerprint": args.fingerprint,
                                       "revision": manifest["revision"]})
        else:
            result = recover_at(root_path(args.root), args.fingerprint, manifest["revision"])
        result["requiresRefresh"] = needs_refresh
        if needs_refresh:
            result["nextAction"] = "Immediately fetch, re-sign, and publish fresh metadata; APT rejects the expired snapshot."
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
    except (PublicationError, OSError, ValueError, KeyError, TypeError, tarfile.TarError) as error:
        # OS/transport exceptions can include machine-local paths; do not print them.
        message = str(error) if isinstance(error, PublicationError) else "repository operation failed; check filesystem and inputs"
        print(json.dumps({"status": "error", "message": message}), file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
