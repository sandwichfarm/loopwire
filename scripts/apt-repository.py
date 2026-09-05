#!/usr/bin/env python3
"""Build and verify immutable signed Loopwire APT repository candidates.

Requires Python's standard library, dpkg-deb, dpkg, gpg, gpgv, and openssl.
The only mutable publication commit point is each suite's InRelease. This
module never uploads files or writes host APT configuration. Its manifest is
an integrity inventory, not a substitute for the pinned OpenPGP trust chain.
"""

import argparse
from datetime import datetime, timezone
from email.utils import format_datetime, parsedate_to_datetime
import gzip
import hashlib
import json
import os
from pathlib import Path, PurePosixPath
import re
import shutil
import stat
import subprocess
import sys
import tempfile
import time


SUITES = {"ubuntu-24.04": "ubuntu24.04", "debian-13": "debian13"}
MANIFEST = "repository-manifest.json"
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\+[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?"
HASH = r"[0-9a-f]{64}"
FINGERPRINT = r"(?:[0-9A-F]{40}|[0-9A-F]{64})"
ROOT = Path(__file__).resolve().parent.parent
PACKAGE_FIELDS = {"name", "version", "architecture", "path", "sha256", "size"}


class RepositoryError(Exception):
    """An invalid or unauthenticated repository candidate."""


def require(condition, message):
    if not condition:
        raise RepositoryError(message)


def run(*args, cwd=None):
    try:
        result = subprocess.run([str(value) for value in args], cwd=cwd,
                                stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False)
    except FileNotFoundError as error:
        raise RepositoryError(f"required tool is missing: {args[0]}") from error
    require(result.returncode == 0,
            f"{args[0]} failed: {result.stderr.decode('utf-8', errors='replace').strip()}")
    return result.stdout


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fingerprint(value):
    require(isinstance(value, str) and re.fullmatch(FINGERPRINT, value) is not None,
            "fingerprint must be the complete uppercase OpenPGP fingerprint")
    return value


def exact_keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), f"invalid {label} fields")


def integer(value, label, minimum=0):
    require(type(value) is int and value >= minimum, f"invalid {label}")
    return value


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON field: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=object_pairs)


def safe_path(value):
    require(isinstance(value, str) and value and not any(ord(char) < 33 or ord(char) > 126 for char in value),
            "inventory paths must contain printable ASCII without whitespace")
    path = PurePosixPath(value)
    require(not path.is_absolute() and str(path) == value and ".." not in path.parts and "\\" not in value,
            f"unsafe inventory path: {value}")
    return value


def classify_path(value):
    safe_path(value)
    if re.fullmatch(rf"keys/{FINGERPRINT}\.asc", value):
        return "immutable"
    for suite, revision in SUITES.items():
        if re.fullmatch(rf"pool/{re.escape(suite)}/main/l/loopwire/loopwire_{VERSION}-1{revision}_amd64\.deb", value):
            return "immutable"
        prefix = f"dists/{suite}/"
        if value in (prefix + "InRelease", prefix + "Release",
                     prefix + "main/binary-amd64/Packages", prefix + "main/binary-amd64/Packages.gz"):
            return "metadata"
        if re.fullmatch(re.escape(prefix) + rf"main/binary-amd64/by-hash/SHA256/{HASH}", value):
            return "immutable"
    raise RepositoryError(f"path is outside the APT repository contract: {value}")


def regular_file(path):
    info = path.lstat()
    require(stat.S_ISREG(info.st_mode) and info.st_nlink == 1,
            f"only regular files without symlinks or hardlinks are allowed: {path}")
    return info


def tree_files(root):
    require(root.is_dir() and not root.is_symlink(), "repository must be a real directory")
    files = set()
    for directory, directories, names in os.walk(root, followlinks=False):
        for name in directories:
            path = Path(directory) / name
            require(not path.is_symlink(), f"symlink directory is forbidden: {path}")
        for name in names:
            path = Path(directory) / name
            regular_file(path)
            files.add(path.relative_to(root).as_posix())
    return files


def parse_control(data):
    text = data.decode("utf-8") if isinstance(data, bytes) else data
    require("\r" not in text and "\x00" not in text, "invalid control-file characters")
    records = []
    current = {}
    field = None
    for line in text.splitlines():
        if not line:
            if current:
                records.append(current)
                current = {}
            field = None
        elif line[0] in " \t":
            require(field is not None, "control-file continuation without a field")
            current[field] += "\n" + line
        else:
            require(":" in line, "malformed control-file field")
            key, value = line.split(":", 1)
            require(re.fullmatch(r"[A-Za-z][A-Za-z0-9-]*", key) is not None, "invalid control-file field name")
            field = key.lower()
            require(field not in current, f"duplicate control-file field: {key}")
            current[field] = value.lstrip(" ")
    if current:
        records.append(current)
    return records


def single_control(data):
    records = parse_control(data)
    require(len(records) == 1, "expected one control-file record")
    return records[0]


def package_info(root, path, suite):
    classify_path(path)
    require(path.startswith(f"pool/{suite}/"), "package belongs to the wrong suite")
    file = root / path
    regular_file(file)
    raw = run("dpkg-deb", "--field", file)
    control = single_control(raw)
    require(control.get("package") == "loopwire", "repository only accepts Package: loopwire")
    require(control.get("architecture") == "amd64", "repository only accepts Architecture: amd64")
    version = control.get("version", "")
    require(re.fullmatch(rf"{VERSION}-1{SUITES[suite]}", version) is not None,
            f"package version does not match suite {suite}: {version}")
    require(Path(path).name == f"loopwire_{version}_amd64.deb", "package filename does not match control identity")
    require(not ({"filename", "size", "md5sum", "sha1", "sha256", "sha512"} & set(control)),
            "package control must not supply repository-owned hash/path fields")
    return {"name": "loopwire", "version": version, "architecture": "amd64", "path": path,
            "sha256": sha256(file), "size": file.stat().st_size}, raw.rstrip(b"\n")


def key_fingerprint(key, home):
    data = run("gpg", "--batch", "--homedir", home, "--with-colons", "--import-options", "show-only",
               "--import", key).decode()
    primary = []
    want_fingerprint = False
    for line in data.splitlines():
        fields = line.split(":")
        if fields[0] == "pub":
            want_fingerprint = True
        elif fields[0] == "fpr" and want_fingerprint:
            primary.append(fingerprint(fields[9]))
            want_fingerprint = False
        elif fields[0] == "sub":
            want_fingerprint = False
    require(len(primary) == 1, "public key must contain exactly one primary OpenPGP key")
    return primary[0]


def signed_release(root, suite, ring, home, expected_fingerprint):
    decoded = Path(home) / f"{suite}.Release"
    status = run("gpgv", "--homedir", home, "--keyring", ring, "--status-fd", "1",
                 "--output", decoded, root / f"dists/{suite}/InRelease").decode()
    valid = [line.split() for line in status.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
    require(len(valid) == 1 and valid[0][-1] == expected_fingerprint,
            f"{suite}: signature does not match the pinned primary fingerprint")
    require(not any(f"[GNUPG:] {flag}" in status for flag in
                    ("EXPKEYSIG", "EXPSIG", "REVKEYSIG", "KEYREVOKED", "KEYEXPIRED", "SIGEXPIRED")),
            f"{suite}: expired or revoked signing identity")
    data = decoded.read_bytes()
    require(data == (root / f"dists/{suite}/Release").read_bytes(),
            f"{suite}: Release differs from signed InRelease payload")
    return single_control(data)


def manifest_revision(manifest):
    unsigned = {key: value for key, value in manifest.items() if key != "revision"}
    return hashlib.sha256(canonical(unsigned)).hexdigest()


def load_inventory(root):
    actual = tree_files(root)
    require(MANIFEST in actual, "missing repository-manifest.json")
    manifest = read_json(root / MANIFEST)
    exact_keys(manifest, {"schemaVersion", "revision", "createdAt", "validUntil", "signingFingerprint", "suites", "files"},
               "repository manifest")
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1, "unsupported manifest schema")
    fingerprint(manifest["signingFingerprint"])
    integer(manifest["createdAt"], "createdAt")
    integer(manifest["validUntil"], "validUntil")
    require(manifest["validUntil"] > manifest["createdAt"], "metadata expiry must follow creation")
    require(manifest["revision"] == manifest_revision(manifest), "manifest revision digest mismatch")
    require(isinstance(manifest["files"], list), "files must be an array")
    inventory = {}
    for entry in manifest["files"]:
        exact_keys(entry, {"path", "sha256", "size", "kind"}, "inventory entry")
        path = safe_path(entry["path"])
        require(path not in inventory, f"duplicate inventory path: {path}")
        require(entry["kind"] == classify_path(path), f"incorrect file classification: {path}")
        integer(entry["size"], "file size")
        require(isinstance(entry["sha256"], str) and re.fullmatch(HASH, entry["sha256"]) is not None,
                f"invalid SHA256: {path}")
        require(path in actual, f"missing inventory file: {path}")
        require((root / path).stat().st_size == entry["size"] and sha256(root / path) == entry["sha256"],
                f"inventory checksum mismatch: {path}")
        if "/by-hash/" in path:
            require(Path(path).name == entry["sha256"], f"by-hash filename/content mismatch: {path}")
        inventory[path] = entry
    require(actual == set(inventory) | {MANIFEST}, "repository has unlisted files")
    return manifest, inventory


def verify_repository(root, public_key, expected_fingerprint, now=None):
    """Verify inventory, pinned signatures, index hashes, and exact package identities."""
    manifest, inventory = load_inventory(root)
    expected = fingerprint(expected_fingerprint) if expected_fingerprint else manifest["signingFingerprint"]
    require(expected == manifest["signingFingerprint"], "manifest fingerprint differs from operator pin")
    now = int(time.time()) if now is None else integer(now, "verification time")
    require(manifest["createdAt"] <= now + 10, "repository metadata is from the future")
    require(manifest["validUntil"] > now, "repository metadata has expired; refresh and re-sign it")
    require(isinstance(manifest["suites"], list) and len(manifest["suites"]) == len(SUITES),
            "repository must contain exactly both supported suites")
    with tempfile.TemporaryDirectory(prefix="loopwire-apt-verify-") as temporary:
        home = Path(temporary)
        require(key_fingerprint(public_key, home) == expected, "trusted public key differs from operator pin")
        ring = home / "trusted.gpg"
        run("gpg", "--batch", "--homedir", home, "--dearmor", "--output", ring, public_key)
        for path in inventory:
            if path.startswith("keys/"):
                require(key_fingerprint(root / path, home) == Path(path).stem, "exported key fingerprint/path mismatch")
        key_path = f"keys/{expected}.asc"
        require(key_path in inventory, "missing fingerprint-addressed bootstrap key")
        # The candidate's bootstrap asset must actually verify the same metadata,
        # not merely carry another packet set with the same primary fingerprint.
        exported_ring = home / "exported.gpg"
        run("gpg", "--batch", "--homedir", home, "--dearmor", "--output", exported_ring, root / key_path)
        seen_suites = set()
        for suite in manifest["suites"]:
            exact_keys(suite, {"name", "architecture", "component", "packages"}, "suite")
            name = suite["name"]
            require(name in SUITES and name not in seen_suites, "invalid or duplicate suite")
            seen_suites.add(name)
            require(suite["architecture"] == "amd64" and suite["component"] == "main", "unsupported suite layout")
            release = signed_release(root, name, ring, home, expected)
            (home / f"{name}.Release").unlink()
            signed_release(root, name, exported_ring, home, expected)
            require(set(release) == {"origin", "label", "suite", "codename", "architectures", "components",
                                     "date", "valid-until", "acquire-by-hash", "sha256"},
                    "signed Release fields are outside the supported repository contract")
            require(release.get("origin") == "Loopwire" and release.get("label") == "Loopwire",
                    "incorrect repository identity")
            require(release.get("suite") == name and release.get("codename") == name, "signed suite mismatch")
            require(release.get("architectures") == "amd64" and release.get("components") == "main",
                    "signed architecture/component mismatch")
            require(release.get("acquire-by-hash") == "yes", "signed metadata must enable by-hash")
            for field, expected_time in (("date", manifest["createdAt"]), ("valid-until", manifest["validUntil"])):
                date = parsedate_to_datetime(release.get(field, ""))
                require(date.tzinfo is not None and int(date.timestamp()) == expected_time,
                        f"signed {field} differs from inventory")
            hashes = {}
            for row in release.get("sha256", "").splitlines():
                if not row.strip():
                    continue
                parts = row.split()
                require(len(parts) == 3 and re.fullmatch(HASH, parts[0]) and parts[1].isdigit(),
                        "invalid signed SHA256 row")
                checksum, size, path = parts
                require(path not in hashes, "duplicate signed index path")
                hashes[path] = (checksum, int(size))
            require(set(hashes) == {"main/binary-amd64/Packages", "main/binary-amd64/Packages.gz"},
                    "signed metadata must cover exactly the supported package indexes")
            for path, (checksum, size) in hashes.items():
                canonical_path = f"dists/{name}/{path}"
                by_hash = f"dists/{name}/main/binary-amd64/by-hash/SHA256/{checksum}"
                for candidate in (canonical_path, by_hash):
                    require(candidate in inventory and inventory[candidate]["sha256"] == checksum
                            and inventory[candidate]["size"] == size, f"signed index checksum mismatch: {candidate}")
            index = (root / f"dists/{name}/main/binary-amd64/Packages").read_bytes()
            require(gzip.decompress((root / f"dists/{name}/main/binary-amd64/Packages.gz").read_bytes()) == index,
                    "compressed index does not match Packages")
            records = parse_control(index)
            require(isinstance(suite["packages"], list) and suite["packages"], "suite has no packages")
            require(len(records) == len(suite["packages"]), "package inventory/index count mismatch")
            packages = {}
            versions = set()
            for entry in suite["packages"]:
                exact_keys(entry, PACKAGE_FIELDS, "package")
                path = safe_path(entry["path"])
                require(path not in packages and path in inventory, "duplicate or missing package inventory path")
                info, _raw = package_info(root, path, name)
                require(entry == info, "package identity/hash does not match inventory")
                require(info["version"] not in versions, "duplicate package version")
                versions.add(info["version"])
                packages[path] = entry
            seen = set()
            for record in records:
                path = record.get("filename")
                require(path in packages and path not in seen, "index contains missing or duplicate package")
                seen.add(path)
                package = packages[path]
                require(record.get("package") == package["name"] and record.get("version") == package["version"]
                        and record.get("architecture") == package["architecture"], "signed package identity mismatch")
                require(record.get("sha256") == package["sha256"] and record.get("size") == str(package["size"]),
                        "signed package checksum mismatch")
        require(seen_suites == set(SUITES), "missing suite")
        # Old immutable packages are outside current indexes after rollback, but
        # still need to satisfy the allowed native-package identity contract.
        for path in inventory:
            if path.startswith("pool/"):
                package_info(root, path, path.split("/")[1])
    return manifest


def export_signer(args, directory):
    expected = fingerprint(args.signing_key)
    gpg = ["gpg", "--batch", "--no-tty"]
    if args.gnupg_home:
        gpg.extend(["--homedir", str(args.gnupg_home)])
    if args.passphrase_file:
        regular_file(args.passphrase_file)
        gpg.extend(["--pinentry-mode", "loopback", "--passphrase-file", str(args.passphrase_file)])
    key = directory / "signer.asc"
    key.write_bytes(run(*gpg, "--export-options", "export-minimal", "--armor", "--export", expected))
    require(key.stat().st_size > 0, "signing public key is missing")
    require(key_fingerprint(key, directory) == expected, "signing key must identify one primary key")
    return gpg, key, expected


def previous_repository(path, key, expected):
    # Refresh/rollback must work after expiry. Authenticate the old snapshot at
    # its signed Date; current validity is checked again on the newly signed output.
    manifest, _inventory = load_inventory(path)
    return verify_repository(path, key, expected, manifest["createdAt"])


def copy_immutable(source, target, manifest):
    for entry in manifest["files"]:
        if entry["kind"] == "immutable":
            destination = target / entry["path"]
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / entry["path"], destination)
            require(sha256(destination) == entry["sha256"] and destination.stat().st_size == entry["size"],
                    "previous immutable file changed while copying the snapshot")


def source_packages(args, output):
    require(re.fullmatch(VERSION, args.version) is not None,
            "APT publication requires X.Y.Z with optional +build metadata; prereleases need a separate version policy")
    source = args.release_dir
    checksums = source / "SHA256SUMS"
    signature = source / "SHA256SUMS.sig"
    regular_file(checksums)
    regular_file(signature)
    run("openssl", "dgst", "-sha256", "-verify", args.release_public_key,
        "-signature", signature, checksums)
    signed = {}
    for line in checksums.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(rf"({HASH}) [ *]([^/\\\s]+)", line)
        require(match is not None, "invalid signed release checksum line")
        checksum, name = match.groups()
        require(name not in signed and name not in (".", ".."), "duplicate or invalid release checksum asset")
        signed[name] = checksum
    expected_assets = {f"loopwire_{args.version}-1{revision}_amd64.deb" for revision in SUITES.values()}
    actual_debs = {path.name for path in source.glob("*.deb")}
    require(actual_debs == expected_assets, "release must contain exactly the two expected native amd64 .deb files")
    result = {}
    for suite, revision in SUITES.items():
        name = f"loopwire_{args.version}-1{revision}_amd64.deb"
        original = source / name
        regular_file(original)
        require(name in signed and sha256(original) == signed[name], f"release package checksum mismatch: {name}")
        path = f"pool/{suite}/main/l/loopwire/{name}"
        destination = output / path
        destination.parent.mkdir(parents=True, exist_ok=True)
        if destination.exists():
            require(sha256(destination) == signed[name], f"same package version has different bytes: {name}")
        else:
            shutil.copyfile(original, destination)
        require(sha256(destination) == signed[name], "release package changed while staging its signed bytes")
        result[suite], _raw = package_info(output, path, suite)
    return result


def write_candidate(args, rollback=False):
    output = args.output
    require(not output.exists() and not output.is_symlink(), "output must not already exist; reuse the completed candidate for publication retries")
    date = int(time.time()) if args.date is None else integer(args.date, "date")
    require(1 <= args.valid_for_days <= 90, "valid-for-days must be between 1 and 90")
    valid_until = date + args.valid_for_days * 86400
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output.name}-", dir=output.parent) as temporary:
        staging_root = Path(temporary)
        working = staging_root / "repository"
        working.mkdir()
        gpg, key, expected = export_signer(args, staging_root)
        previous_path = args.repository if rollback else args.previous
        previous = previous_repository(previous_path, key, expected) if previous_path else None
        if previous:
            require(date >= previous["createdAt"], "new metadata Date must not precede the previous revision")
            copy_immutable(previous_path, working, previous)
        suites = previous["suites"] if previous else [
            {"name": name, "architecture": "amd64", "component": "main", "packages": []} for name in SUITES]
        if not rollback:
            added = source_packages(args, working)
            for suite in suites:
                package = added[suite["name"]]
                for old in suite["packages"]:
                    comparison = subprocess.run(["dpkg", "--compare-versions", package["version"], "ge", old["version"]],
                                                stdout=subprocess.DEVNULL, stderr=subprocess.PIPE)
                    require(comparison.returncode == 0,
                            "new package version is lower than a published version; use explicit rollback")
                if not any(old["version"] == package["version"] for old in suite["packages"]):
                    suite["packages"].append(package)
                suite["packages"].sort(key=lambda entry: entry["path"])
        exported = working / f"keys/{expected}.asc"
        exported.parent.mkdir(exist_ok=True)
        if exported.exists():
            require(exported.read_bytes() == key.read_bytes(),
                    "fingerprint-addressed key bytes changed; rotate with a new identity and bootstrap trust first")
        else:
            shutil.copyfile(key, exported)
        for suite in suites:
            name = suite["name"]
            suite_dir = working / f"dists/{name}"
            binary = suite_dir / "main/binary-amd64"
            by_hash = binary / "by-hash/SHA256"
            by_hash.mkdir(parents=True, exist_ok=True)
            paragraphs = []
            for entry in suite["packages"]:
                info, raw = package_info(working, entry["path"], name)
                require(info == entry, "retained package differs from validated inventory")
                paragraphs.append(raw + (f"\nFilename: {entry['path']}\nSize: {entry['size']}\n"
                                         f"SHA256: {entry['sha256']}\n\n").encode())
            index = b"".join(paragraphs)
            (binary / "Packages").write_bytes(index)
            (binary / "Packages.gz").write_bytes(gzip.compress(index, compresslevel=9, mtime=0))
            hash_rows = []
            for index_name in ("Packages", "Packages.gz"):
                file = binary / index_name
                checksum = sha256(file)
                immutable = by_hash / checksum
                if immutable.exists():
                    require(sha256(immutable) == checksum, "immutable by-hash collision")
                else:
                    shutil.copyfile(file, immutable)
                hash_rows.append(f" {checksum} {file.stat().st_size} main/binary-amd64/{index_name}\n")
            release = ("Origin: Loopwire\nLabel: Loopwire\n"
                       f"Suite: {name}\nCodename: {name}\nArchitectures: amd64\nComponents: main\n"
                       f"Date: {format_datetime(datetime.fromtimestamp(date, timezone.utc), usegmt=True)}\n"
                       f"Valid-Until: {format_datetime(datetime.fromtimestamp(valid_until, timezone.utc), usegmt=True)}\n"
                       "Acquire-By-Hash: yes\nSHA256:\n" + "".join(hash_rows))
            (suite_dir / "Release").write_text(release, encoding="utf-8")
            run(*gpg, "--yes", "--faked-system-time", f"{date}!", "--digest-algo", "SHA256",
                "--local-user", expected, "--armor", "--clearsign", "--output", suite_dir / "InRelease",
                suite_dir / "Release")
        files = [{"path": path, "sha256": sha256(working / path), "size": (working / path).stat().st_size,
                  "kind": classify_path(path)} for path in sorted(tree_files(working))]
        manifest = {"schemaVersion": 1, "createdAt": date, "validUntil": valid_until,
                    "signingFingerprint": expected, "suites": suites, "files": files}
        manifest["revision"] = manifest_revision(manifest)
        (working / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        verify_repository(working, key, expected, date)
        working.rename(output)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="generate a candidate from signed native release assets")
    build.add_argument("--release-dir", type=Path, required=True)
    build.add_argument("--version", required=True)
    build.add_argument("--release-public-key", type=Path, default=ROOT / "packaging/release-signing-public.pem",
                       help="trusted release checksum PEM (override for fixture keys)")
    build.add_argument("--previous", type=Path, help="verified previous snapshot whose immutable history is retained")
    rollback = commands.add_parser("rollback", help="freshly sign a previous snapshot's package set (also refreshes expiry)")
    rollback.add_argument("--repository", type=Path, required=True)
    for command in (build, rollback):
        command.add_argument("--output", type=Path, required=True)
        command.add_argument("--signing-key", required=True, help="uppercase primary OpenPGP fingerprint")
        command.add_argument("--gnupg-home", type=Path, help="isolated GnuPG home containing the signing identity")
        command.add_argument("--passphrase-file", type=Path,
                             help="optional protected file containing the signing-key passphrase; never pass it as a value")
        command.add_argument("--date", type=int, help="metadata/signature creation time as Unix epoch seconds (default: now)")
        command.add_argument("--valid-for-days", type=int, default=30)
    verify = commands.add_parser("verify", help="verify the inventory and complete pinned APT trust chain")
    verify.add_argument("--repository", type=Path, required=True)
    verify.add_argument("--public-key", type=Path, required=True, help="independently trusted ASCII-armored public key")
    verify.add_argument("--fingerprint", help="expected uppercase primary fingerprint (otherwise derived from trusted public key)")
    verify.add_argument("--now", type=int, help="explicit verification time for fixture or historical-snapshot validation")
    args = parser.parse_args()
    if args.command == "verify":
        manifest = verify_repository(args.repository, args.public_key, args.fingerprint, args.now)
    else:
        manifest = write_candidate(args, rollback=args.command == "rollback")
    print(json.dumps({key: manifest[key] for key in
                      ("revision", "signingFingerprint", "createdAt", "validUntil", "suites")}, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (RepositoryError, OSError, ValueError, KeyError, TypeError, EOFError, OverflowError) as error:
        print(f"apt-repository: {error}", file=sys.stderr)
        sys.exit(1)
