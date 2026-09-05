#!/usr/bin/env python3
"""Build and verify immutable signed Loopwire Fedora repository candidates.

Requires Python's standard library, createrepo_c, rpm, rpmkeys, rpmsign,
gpg, gpgv, and openssl. The publisher retains immutable package and metadata
objects globally, writes repomd.xml.asc first, and atomically replaces
repomd.xml as the public commit point. This module never publishes files or
changes host repository configuration.

The explicit --date fixes repository timestamps and GnuPG signature creation
times. Byte-for-byte repeatability still requires the pinned Fedora tool image,
the same key material, and a deterministic OpenPGP algorithm; a prior package
with identical source bytes is reused rather than signed again.
"""

import argparse
import gzip
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
import tempfile
import time
import xml.etree.ElementTree as ET


SCHEMA = "loopwire.rpm-repository.v1"
MANIFEST = "repository-manifest.json"
TARGET = {"distribution": "fedora", "release": "44", "architecture": "x86_64"}
VERSION = r"(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)\.(?:0|[1-9][0-9]*)(?:\+[0-9A-Za-z]+(?:\.[0-9A-Za-z]+)*)?"
HASH = r"[0-9a-f]{64}"
FINGERPRINT = r"(?:[0-9A-F]{40}|[0-9A-F]{64})"
PACKAGE_FIELDS = {
    "name", "version", "release", "architecture", "path",
    "sourceReleaseSha256", "distributedSha256", "size",
}
FILE_FIELDS = {"path", "sha256", "size", "kind"}
ROOT = Path(__file__).resolve().parent.parent
REPO_NS = "http://linux.duke.edu/metadata/repo"
COMMON_NS = "http://linux.duke.edu/metadata/common"


class RepositoryError(Exception):
    """An invalid or unauthenticated RPM repository candidate."""


def require(condition, message):
    if not condition:
        raise RepositoryError(message)


def run(*args, cwd=None, env=None):
    try:
        result = subprocess.run(
            [str(value) for value in args], cwd=cwd, env=env,
            stdout=subprocess.PIPE, stderr=subprocess.PIPE, check=False,
        )
    except FileNotFoundError as error:
        raise RepositoryError(f"required tool is missing: {args[0]}") from error
    require(
        result.returncode == 0,
        f"{args[0]} failed: {result.stderr.decode('utf-8', errors='replace').strip()}",
    )
    return result.stdout


def canonical(value):
    return json.dumps(value, sort_keys=True, separators=(",", ":")).encode("utf-8")


def sha256(path):
    with path.open("rb") as stream:
        return hashlib.file_digest(stream, "sha256").hexdigest()


def fingerprint(value):
    require(
        isinstance(value, str) and re.fullmatch(FINGERPRINT, value) is not None,
        "fingerprint must be the complete uppercase OpenPGP fingerprint",
    )
    return value


def hash_value(value, label):
    require(isinstance(value, str) and re.fullmatch(HASH, value) is not None, f"invalid {label}")
    return value


def integer(value, label, minimum=0):
    require(type(value) is int and value >= minimum, f"invalid {label}")
    return value


def exact_keys(value, expected, label):
    require(isinstance(value, dict) and set(value) == set(expected), f"invalid {label} fields")


def object_pairs(pairs):
    result = {}
    for key, value in pairs:
        require(key not in result, f"duplicate JSON field: {key}")
        result[key] = value
    return result


def read_json(path):
    return json.loads(path.read_text(encoding="utf-8"), object_pairs_hook=object_pairs)


def safe_path(value):
    require(
        isinstance(value, str) and value
        and not any(ord(character) < 33 or ord(character) > 126 for character in value),
        "inventory paths must contain printable ASCII without whitespace",
    )
    path = PurePosixPath(value)
    require(
        not path.is_absolute() and str(path) == value and ".." not in path.parts and "\\" not in value,
        f"unsafe inventory path: {value}",
    )
    return value


def classify_path(value):
    safe_path(value)
    if re.fullmatch(rf"keys/{FINGERPRINT}\.asc", value):
        return "immutable"
    if re.fullmatch(rf"packages/loopwire-{VERSION}-1\.fc44\.x86_64\.rpm", value):
        return "immutable"
    if re.fullmatch(rf"repodata/{HASH}-(?:primary|filelists|other)\.xml\.gz", value):
        return "immutable"
    if value in ("repodata/repomd.xml", "repodata/repomd.xml.asc"):
        return "metadata"
    raise RepositoryError(f"path is outside the Fedora repository contract: {value}")


def regular_file(path):
    information = path.lstat()
    require(
        stat.S_ISREG(information.st_mode) and information.st_nlink == 1,
        f"only regular files without symlinks or hardlinks are allowed: {path}",
    )
    return information


def real_directory(path, label):
    require(path.is_dir() and not path.is_symlink(), f"{label} must be a real directory")
    return path


def tree_files(root):
    real_directory(root, "repository")
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


def key_fingerprint(key, home):
    data = run(
        "gpg", "--batch", "--homedir", home, "--with-colons",
        "--import-options", "show-only", "--import", key,
    ).decode("utf-8")
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


def manifest_revision(manifest):
    unsigned = {key: value for key, value in manifest.items() if key != "revision"}
    return hashlib.sha256(canonical(unsigned)).hexdigest()


def rpm_identity(path):
    regular_file(path)
    fields = run(
        "rpm", "-qp", "--queryformat",
        "%{NAME}\n%{VERSION}\n%{RELEASE}\n%{ARCH}\n%{EPOCHNUM}\n", path,
    ).decode("utf-8").splitlines()
    require(len(fields) == 5, "RPM identity query returned unexpected fields")
    name, version, release, architecture, epoch = fields
    require(name == "loopwire", "repository only accepts RPM Name: loopwire")
    require(re.fullmatch(VERSION, version) is not None, f"unsupported RPM version: {version}")
    require(release == "1.fc44", f"repository only accepts RPM Release: 1.fc44, got {release}")
    require(architecture == "x86_64", f"repository only accepts RPM Architecture: x86_64, got {architecture}")
    require(epoch in ("0", "(none)"), "repository RPM must not set a nonzero epoch")
    return name, version, release, architecture


def rpm_has_signature(path):
    output = run(
        "rpm", "-qp", "--queryformat",
        "%{OPENPGP:pgpsig}\n%{SIGPGP:pgpsig}\n%{SIGGPG:pgpsig}\n"
        "%{RSAHEADER:pgpsig}\n%{DSAHEADER:pgpsig}\n", path,
    ).decode("utf-8", errors="replace")
    return any(value.strip() not in ("", "(none)") for value in output.splitlines())


def verify_rpm_digest(path):
    run("rpmkeys", "--nosignature", "--checksig", path)


def verify_rpm_signature(path, public_key):
    require(rpm_has_signature(path), f"RPM has no OpenPGP package signature: {path}")
    with tempfile.TemporaryDirectory(prefix="loopwire-rpm-keyring-") as temporary:
        database = Path(temporary) / "rpmdb"
        database.mkdir()
        run("rpmkeys", "--dbpath", database, "--import", public_key)
        run("rpmkeys", "--dbpath", database, "--checksig", path)


def package_info(root, path, source_hash, public_key):
    classify_path(path)
    require(path.startswith("packages/"), "RPM path is outside packages/")
    package = root / path
    verify_rpm_digest(package)
    verify_rpm_signature(package, public_key)
    name, version, release, architecture = rpm_identity(package)
    require(
        Path(path).name == f"{name}-{version}-{release}.{architecture}.rpm",
        "RPM filename does not match its NEVRA identity",
    )
    return {
        "name": name,
        "version": version,
        "release": release,
        "architecture": architecture,
        "path": path,
        "sourceReleaseSha256": hash_value(source_hash, "source release SHA256"),
        "distributedSha256": sha256(package),
        "size": package.stat().st_size,
    }


def verify_detached_signature(data, signature, keyring, home, expected):
    armored = signature.read_text(encoding="ascii")
    require(
        armored.startswith("-----BEGIN PGP SIGNATURE-----\n")
        and armored.rstrip().endswith("-----END PGP SIGNATURE-----"),
        "repomd.xml signature must be detached ASCII armor",
    )
    status = run(
        "gpgv", "--homedir", home, "--keyring", keyring,
        "--status-fd", "1", signature, data,
    ).decode("utf-8")
    valid = [line.split() for line in status.splitlines() if line.startswith("[GNUPG:] VALIDSIG ")]
    require(
        len(valid) == 1 and valid[0][-1] == expected,
        "repomd.xml signature does not match the pinned primary fingerprint",
    )
    require(
        not any(f"[GNUPG:] {flag}" in status for flag in (
            "EXPKEYSIG", "EXPSIG", "REVKEYSIG", "KEYREVOKED", "KEYEXPIRED", "SIGEXPIRED",
        )),
        "repomd.xml uses an expired or revoked signing identity",
    )


def load_inventory(root):
    actual = tree_files(root)
    require(MANIFEST in actual, "missing repository-manifest.json")
    manifest = read_json(root / MANIFEST)
    exact_keys(
        manifest,
        {"schema", "schemaVersion", "revision", "signingFingerprint", "createdAt",
         "validUntil", "target", "packages", "files"},
        "repository manifest",
    )
    require(manifest["schema"] == SCHEMA, "unsupported repository manifest schema")
    require(type(manifest["schemaVersion"]) is int and manifest["schemaVersion"] == 1,
            "unsupported repository manifest schema version")
    fingerprint(manifest["signingFingerprint"])
    integer(manifest["createdAt"], "createdAt")
    integer(manifest["validUntil"], "validUntil")
    require(manifest["validUntil"] > manifest["createdAt"], "metadata expiry must follow creation")
    exact_keys(manifest["target"], TARGET, "repository target")
    require(manifest["target"] == TARGET, "repository target must be Fedora 44 x86_64")
    require(manifest["revision"] == manifest_revision(manifest), "manifest revision digest mismatch")
    require(isinstance(manifest["packages"], list) and manifest["packages"], "packages must be a nonempty array")
    require(isinstance(manifest["files"], list), "files must be an array")
    inventory = {}
    for entry in manifest["files"]:
        exact_keys(entry, FILE_FIELDS, "inventory entry")
        path = safe_path(entry["path"])
        require(path not in inventory, f"duplicate inventory path: {path}")
        require(entry["kind"] == classify_path(path), f"incorrect file classification: {path}")
        integer(entry["size"], "file size")
        hash_value(entry["sha256"], f"SHA256 for {path}")
        require(path in actual, f"missing inventory file: {path}")
        file = root / path
        require(
            file.stat().st_size == entry["size"] and sha256(file) == entry["sha256"],
            f"inventory checksum mismatch: {path}",
        )
        if path.startswith("repodata/") and entry["kind"] == "immutable":
            require(Path(path).name.startswith(entry["sha256"] + "-"),
                    f"repodata content filename/checksum mismatch: {path}")
        inventory[path] = entry
    require(actual == set(inventory) | {MANIFEST}, "repository has unlisted files")
    return manifest, inventory


def xml(root, name):
    values = root.findall(f"{{{REPO_NS}}}{name}")
    require(len(values) == 1, f"repomd.xml must contain exactly one {name}")
    return values[0]


def parse_repomd(root, manifest, inventory):
    path = root / "repodata/repomd.xml"
    raw = path.read_bytes()
    require(b"<!DOCTYPE" not in raw and b"<!ENTITY" not in raw, "repomd.xml must not declare entities")
    document = ET.fromstring(raw)
    require(document.tag == f"{{{REPO_NS}}}repomd", "invalid repomd.xml root")
    created = str(manifest["createdAt"])
    require((xml(document, "revision").text or "") == created,
            "signed repomd revision differs from manifest createdAt")
    tags = xml(document, "tags")
    distro = tags.findall(f"{{{REPO_NS}}}distro")
    require(
        len(distro) == 1 and distro[0].attrib == {"cpeid": "cpe:/o:fedoraproject:fedora:44"}
        and (distro[0].text or "") == "Fedora 44",
        "signed repomd distro tag differs from Fedora 44",
    )
    content = [element.text or "" for element in tags.findall(f"{{{REPO_NS}}}content")]
    require(content == [SCHEMA], "signed repomd content tag differs from repository schema")
    repo_tags = [element.text or "" for element in tags.findall(f"{{{REPO_NS}}}repo")]
    expiry_tag = f"loopwire-valid-until:{manifest['validUntil']}"
    source_tags = {}
    for value in repo_tags:
        if value == expiry_tag:
            continue
        match = re.fullmatch(rf"loopwire-source-sha256:(packages/[^:]+):({HASH})", value)
        require(match is not None, f"unsupported signed repomd repository tag: {value}")
        package_path, source_hash = match.groups()
        require(package_path not in source_tags, "duplicate signed RPM source provenance tag")
        source_tags[package_path] = source_hash
    require(repo_tags.count(expiry_tag) == 1, "signed repomd metadata expiry is missing or duplicated")
    require(len(source_tags) + 1 == len(repo_tags), "signed repomd repository tags are duplicated")

    metadata = {}
    data_elements = document.findall(f"{{{REPO_NS}}}data")
    require(len(data_elements) == 3, "repomd.xml must describe exactly primary, filelists, and other metadata")
    for data in data_elements:
        kind = data.attrib.get("type")
        require(set(data.attrib) == {"type"} and kind in {"primary", "filelists", "other"}
                and kind not in metadata, "invalid or duplicate repomd data type")
        checksum = xml(data, "checksum")
        open_checksum = xml(data, "open-checksum")
        location = xml(data, "location")
        timestamp = xml(data, "timestamp")
        size = xml(data, "size")
        open_size = xml(data, "open-size")
        require(checksum.attrib == {"type": "sha256"}, "repomd metadata checksum must use SHA256")
        require(open_checksum.attrib == {"type": "sha256"}, "repomd open checksum must use SHA256")
        digest = hash_value(checksum.text or "", "repomd metadata SHA256")
        open_digest = hash_value(open_checksum.text or "", "repomd open SHA256")
        require(set(location.attrib) == {"href"}, "invalid repomd metadata location")
        relative = safe_path(location.attrib["href"])
        require(classify_path(relative) == "immutable" and relative.startswith("repodata/"),
                "repomd points outside immutable metadata objects")
        require(relative in inventory, f"repomd metadata object is missing: {relative}")
        require(inventory[relative]["sha256"] == digest, f"repomd checksum mismatch: {relative}")
        require((timestamp.text or "") == created, f"repomd timestamp mismatch: {relative}")
        require((size.text or "").isdigit() and int(size.text) == inventory[relative]["size"],
                f"repomd size mismatch: {relative}")
        compressed = (root / relative).read_bytes()
        try:
            uncompressed = gzip.decompress(compressed)
        except (gzip.BadGzipFile, EOFError, OSError) as error:
            raise RepositoryError(f"invalid gzip metadata: {relative}") from error
        require((open_size.text or "").isdigit() and int(open_size.text) == len(uncompressed),
                f"repomd open size mismatch: {relative}")
        require(hashlib.sha256(uncompressed).hexdigest() == open_digest,
                f"repomd open checksum mismatch: {relative}")
        metadata[kind] = uncompressed
    return metadata, source_tags


def primary_packages(primary):
    require(b"<!DOCTYPE" not in primary and b"<!ENTITY" not in primary,
            "primary metadata must not declare entities")
    document = ET.fromstring(primary)
    require(document.tag == f"{{{COMMON_NS}}}metadata", "invalid primary metadata root")
    records = document.findall(f"{{{COMMON_NS}}}package")
    require(document.attrib == {"packages": str(len(records))}, "primary metadata package count mismatch")
    result = {}
    for record in records:
        require(record.attrib == {"type": "rpm"}, "primary metadata contains a non-RPM package")
        values = {}
        for name in ("name", "arch", "version", "checksum", "location", "size"):
            matches = record.findall(f"{{{COMMON_NS}}}{name}")
            require(len(matches) == 1, f"primary metadata package has invalid {name}")
            values[name] = matches[0]
        path = safe_path(values["location"].attrib.get("href"))
        require(set(values["location"].attrib) == {"href"} and path not in result,
                "primary metadata contains a duplicate or invalid package path")
        version = values["version"].attrib
        require(set(version) == {"epoch", "ver", "rel"}, "invalid primary RPM version fields")
        checksum = values["checksum"]
        require(checksum.attrib == {"type": "sha256", "pkgid": "YES"},
                "primary RPM checksum must be the SHA256 package id")
        size = values["size"].attrib
        require("package" in size and size["package"].isdigit(), "invalid primary RPM package size")
        result[path] = {
            "name": values["name"].text or "",
            "version": version["ver"],
            "release": version["rel"],
            "architecture": values["arch"].text or "",
            "epoch": version["epoch"],
            "sha256": hash_value(checksum.text or "", f"primary RPM SHA256 for {path}"),
            "size": int(size["package"]),
        }
    return result


def verify_repository(root, public_key, expected_fingerprint, now=None):
    """Verify the inventory, signed metadata, RPM signatures, and exact Fedora identity."""
    manifest, inventory = load_inventory(root)
    expected = fingerprint(expected_fingerprint) if expected_fingerprint else manifest["signingFingerprint"]
    require(expected == manifest["signingFingerprint"], "manifest fingerprint differs from operator pin")
    now = int(time.time()) if now is None else integer(now, "verification time")
    require(manifest["createdAt"] <= now + 10, "repository metadata is from the future")
    require(manifest["validUntil"] > now, "repository metadata has expired; refresh and re-sign it")
    regular_file(public_key)
    with tempfile.TemporaryDirectory(prefix="loopwire-rpm-verify-") as temporary:
        home = Path(temporary)
        require(key_fingerprint(public_key, home) == expected, "trusted public key differs from operator pin")
        trusted_ring = home / "trusted.gpg"
        run("gpg", "--batch", "--homedir", home, "--dearmor", "--output", trusted_ring, public_key)
        key_path = f"keys/{expected}.asc"
        require(key_path in inventory, "missing fingerprint-addressed repository key")
        exported_key = root / key_path
        require(key_fingerprint(exported_key, home) == expected, "exported key fingerprint/path mismatch")
        exported_ring = home / "exported.gpg"
        run("gpg", "--batch", "--homedir", home, "--dearmor", "--output", exported_ring, exported_key)
        repomd = root / "repodata/repomd.xml"
        signature = root / "repodata/repomd.xml.asc"
        require("repodata/repomd.xml" in inventory and "repodata/repomd.xml.asc" in inventory,
                "repository is missing signed repomd metadata")
        verify_detached_signature(repomd, signature, trusted_ring, home, expected)
        verify_detached_signature(repomd, signature, exported_ring, home, expected)
        metadata, source_tags = parse_repomd(root, manifest, inventory)
        indexed = primary_packages(metadata["primary"])
        require(len(indexed) == len(manifest["packages"]), "manifest/primary package count mismatch")
        packages = {}
        versions = set()
        for entry in manifest["packages"]:
            exact_keys(entry, PACKAGE_FIELDS, "package inventory entry")
            path = safe_path(entry["path"])
            require(path not in packages and path in inventory and path in source_tags,
                    "duplicate or missing package inventory path")
            require(inventory[path]["kind"] == "immutable", "RPM package must be immutable")
            info = package_info(root, path, source_tags[path], public_key)
            verify_rpm_signature(root / path, exported_key)
            require(entry == info, f"RPM identity/hash differs from package inventory: {path}")
            require(inventory[path]["sha256"] == info["distributedSha256"]
                    and inventory[path]["size"] == info["size"], f"file inventory differs for RPM: {path}")
            require(info["version"] not in versions, "duplicate RPM version in repository")
            versions.add(info["version"])
            packages[path] = info
        require(set(source_tags) == set(packages), "signed source provenance does not match package inventory")
        require(set(indexed) == set(packages), "primary metadata package set differs from manifest")
        for path, package in packages.items():
            record = indexed[path]
            require(
                record == {
                    "name": package["name"], "version": package["version"],
                    "release": package["release"], "architecture": package["architecture"],
                    "epoch": "0", "sha256": package["distributedSha256"], "size": package["size"],
                },
                f"signed primary metadata differs from RPM package: {path}",
            )
    return manifest


def export_signer(args, directory):
    expected = fingerprint(args.signing_key)
    home = real_directory(args.gnupg_home, "GnuPG home")
    if args.passphrase_file:
        information = regular_file(args.passphrase_file)
        require(information.st_mode & 0o077 == 0, "passphrase file must not be group/world accessible")
    gpg = ["gpg", "--batch", "--no-tty", "--homedir", str(home)]
    if args.passphrase_file:
        gpg.extend(["--pinentry-mode", "loopback", "--passphrase-file", str(args.passphrase_file)])
    run(*gpg, "--list-secret-keys", expected)
    key = directory / "signer.asc"
    key.write_bytes(run(*gpg, "--export-options", "export-minimal", "--armor", "--export", expected))
    require(key.stat().st_size > 0, "signing public key is missing")
    require(key_fingerprint(key, directory) == expected, "signing key must identify one primary key")
    return gpg, key, expected


def signing_wrapper(directory, gpg_home, passphrase_file, date):
    executable = shutil.which("gpg")
    require(executable is not None, "required tool is missing: gpg")
    arguments = [
        executable, "--batch", "--no-tty", "--pinentry-mode", "loopback",
        "--homedir", str(gpg_home), "--faked-system-time", f"{date}!",
    ]
    if passphrase_file:
        arguments.extend(["--passphrase-file", str(passphrase_file)])
    wrapper = directory / "rpm-gpg-wrapper"
    wrapper.write_text("#!/bin/sh\nexec " + " ".join(shlex.quote(value) for value in arguments)
                       + ' "$@"\n', encoding="utf-8")
    wrapper.chmod(0o700)
    return wrapper


def sign_rpm(package, expected, gpg_home, passphrase_file, date, directory, public_key):
    wrapper = signing_wrapper(directory, gpg_home, passphrase_file, date)
    run(
        "rpmsign", "--resign",
        "--define", f"_openpgp_sign_id {expected}",
        "--define", f"_gpg_path {gpg_home}",
        "--define", f"__gpg {wrapper}",
        package,
    )
    verify_rpm_signature(package, public_key)


def rpm_version_compare(left, right):
    require(re.fullmatch(VERSION, left) and re.fullmatch(VERSION, right), "invalid RPM version comparison")
    expression = f"%{{lua:print(rpm.vercmp('{left}', '{right}'))}}"
    value = run("rpm", "--eval", expression).decode("ascii").strip()
    require(value in ("-1", "0", "1"), "rpm version comparison returned an invalid result")
    return int(value)


def previous_repository(path, key, expected):
    manifest, _inventory = load_inventory(path)
    return verify_repository(path, key, expected, manifest["createdAt"])


def copy_immutable(source, target, manifest):
    for entry in manifest["files"]:
        if entry["kind"] != "immutable":
            continue
        destination = target / entry["path"]
        destination.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source / entry["path"], destination)
        require(
            sha256(destination) == entry["sha256"] and destination.stat().st_size == entry["size"],
            "previous immutable file changed while copying the snapshot",
        )


def signed_release_package(args, working, packages, expected, key, staging, date):
    require(
        re.fullmatch(VERSION, args.version) is not None,
        "Fedora publication requires X.Y.Z with optional +build metadata",
    )
    release = real_directory(args.release_dir, "release directory")
    checksums = release / "SHA256SUMS"
    signature = release / "SHA256SUMS.sig"
    regular_file(checksums)
    regular_file(signature)
    regular_file(args.release_public_key)
    run(
        "openssl", "dgst", "-sha256", "-verify", args.release_public_key,
        "-signature", signature, checksums,
    )
    signed = {}
    for line in checksums.read_text(encoding="utf-8").splitlines():
        match = re.fullmatch(rf"({HASH}) [ *]([^/\\\s]+)", line)
        require(match is not None, "invalid signed release checksum line")
        checksum, name = match.groups()
        require(name not in signed and name not in (".", ".."), "duplicate or invalid release checksum asset")
        signed[name] = checksum
    filename = f"loopwire-{args.version}-1.fc44.x86_64.rpm"
    actual_rpms = {path.name for path in release.glob("*.rpm")}
    known_release_rpms = {filename, f"loopwire-{args.version}-1.x86_64.rpm"}
    require(filename in actual_rpms and actual_rpms <= known_release_rpms,
            "release must contain the Fedora 44 RPM and no unknown RPM artifacts")
    source = release / filename
    regular_file(source)
    source_hash = sha256(source)
    require(filename in signed and signed[filename] == source_hash,
            f"signed release checksum differs for {filename}")
    verify_rpm_digest(source)
    name, version, rpm_release, architecture = rpm_identity(source)
    require(version == args.version, "RPM version differs from requested repository version")
    path = f"packages/{filename}"
    for previous in packages:
        require(rpm_version_compare(version, previous["version"]) >= 0,
                "new RPM version is lower than a published version; use explicit rollback")
    matches = [entry for entry in packages if entry["version"] == version]
    require(len(matches) <= 1, "previous repository has duplicate RPM versions")
    if matches:
        previous = matches[0]
        require(previous["path"] == path and previous["sourceReleaseSha256"] == source_hash,
                "same RPM version has different source release bytes")
        require((working / path).is_file(), "retained RPM package is missing")
        return
    destination = working / path
    destination.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(source, destination)
    require(sha256(destination) == source_hash, "release RPM changed while copying to repository staging")
    sign_rpm(destination, expected, args.gnupg_home, args.passphrase_file, date, staging, key)
    packages.append(package_info(working, path, source_hash, key))
    packages.sort(key=lambda entry: entry["path"])


def generate_metadata(working, packages, date, valid_until, gpg, expected, staging):
    for package in packages:
        path = working / package["path"]
        regular_file(path)
        os.utime(path, (date, date), follow_symlinks=False)
    package_list = staging / "packages.list"
    package_list.write_text("".join(entry["path"] + "\n" for entry in packages), encoding="utf-8")
    generated = staging / "generated"
    generated.mkdir()
    repo_tags = [f"loopwire-valid-until:{valid_until}"]
    repo_tags.extend(
        f"loopwire-source-sha256:{entry['path']}:{entry['sourceReleaseSha256']}"
        for entry in packages
    )
    command = [
        "createrepo_c", "--quiet", "--no-database", "--checksum", "sha256",
        "--repomd-checksum", "sha256", "--general-compress-type", "gz",
        "--unique-md-filenames", "--workers", "1", "--changelog-limit", "0",
        "--revision", str(date), "--set-timestamp-to-revision",
        "--distro", "cpe:/o:fedoraproject:fedora:44,Fedora 44",
        "--content", SCHEMA, "--pkglist", package_list, "--outputdir", generated,
    ]
    for tag in repo_tags:
        command.extend(["--repo", tag])
    command.append(working)
    run(*command)
    generated_repodata = generated / "repodata"
    real_directory(generated_repodata, "generated repodata")
    destination = working / "repodata"
    destination.mkdir(parents=True, exist_ok=True)
    for path in sorted(generated_repodata.iterdir()):
        regular_file(path)
        relative = f"repodata/{path.name}"
        classify_path(relative)
        target = destination / path.name
        if target.exists() and path.name != "repomd.xml":
            require(sha256(target) == sha256(path), f"immutable repodata collision: {path.name}")
        else:
            shutil.copyfile(path, target)
    repomd = destination / "repomd.xml"
    signature = destination / "repomd.xml.asc"
    run(
        *gpg, "--yes", "--faked-system-time", f"{date}!", "--digest-algo", "SHA256",
        "--local-user", expected, "--armor", "--detach-sign", "--output", signature, repomd,
    )


def write_candidate(args, rollback=False):
    output = args.output
    require(
        not output.exists() and not output.is_symlink(),
        "output must not already exist; reuse a completed candidate for publication retries",
    )
    date = int(time.time()) if args.date is None else integer(args.date, "date")
    require(1 <= args.valid_for_days <= 90, "valid-for-days must be between 1 and 90")
    valid_until = date + args.valid_for_days * 86400
    output.parent.mkdir(parents=True, exist_ok=True)
    with tempfile.TemporaryDirectory(prefix=f".{output.name}-", dir=output.parent) as temporary:
        staging = Path(temporary)
        working = staging / "repository"
        working.mkdir()
        gpg, key, expected = export_signer(args, staging)
        previous_path = args.repository if rollback else args.previous
        previous = previous_repository(previous_path, key, expected) if previous_path else None
        if previous:
            require(date >= previous["createdAt"], "new metadata date must not precede the previous revision")
            copy_immutable(previous_path, working, previous)
            packages = json.loads(json.dumps(previous["packages"]))
        else:
            packages = []
        if not rollback:
            signed_release_package(args, working, packages, expected, key, staging, date)
        require(packages, "repository package set must not be empty")
        exported = working / f"keys/{expected}.asc"
        exported.parent.mkdir(parents=True, exist_ok=True)
        if exported.exists():
            require(exported.read_bytes() == key.read_bytes(),
                    "fingerprint-addressed key bytes changed; rotate trust before changing exported packets")
        else:
            shutil.copyfile(key, exported)
        generate_metadata(working, packages, date, valid_until, gpg, expected, staging)
        files = [
            {
                "path": path, "sha256": sha256(working / path),
                "size": (working / path).stat().st_size, "kind": classify_path(path),
            }
            for path in sorted(tree_files(working))
        ]
        manifest = {
            "schema": SCHEMA,
            "schemaVersion": 1,
            "signingFingerprint": expected,
            "createdAt": date,
            "validUntil": valid_until,
            "target": TARGET,
            "packages": packages,
            "files": files,
        }
        manifest["revision"] = manifest_revision(manifest)
        (working / MANIFEST).write_text(json.dumps(manifest, indent=2, sort_keys=True) + "\n", encoding="utf-8")
        verify_repository(working, key, expected, date)
        working.rename(output)
    return manifest


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    commands = parser.add_subparsers(dest="command", required=True)
    build = commands.add_parser("build", help="generate a Fedora candidate from signed native release assets")
    build.add_argument("--release-dir", type=Path, required=True)
    build.add_argument("--version", required=True)
    build.add_argument(
        "--release-public-key", type=Path, default=ROOT / "packaging/release-signing-public.pem",
        help="trusted release checksum PEM (override for fixture keys)",
    )
    build.add_argument("--previous", type=Path, help="verified previous snapshot whose immutable history is retained")
    rollback = commands.add_parser("rollback", help="freshly sign a retained snapshot's previous package set")
    rollback.add_argument("--repository", type=Path, required=True)
    for command in (build, rollback):
        command.add_argument("--output", type=Path, required=True)
        command.add_argument("--signing-key", required=True, help="uppercase primary OpenPGP fingerprint")
        command.add_argument("--gnupg-home", type=Path, required=True,
                             help="isolated GnuPG home containing the signing identity")
        command.add_argument("--passphrase-file", type=Path,
                             help="protected file containing the signing-key passphrase; never pass the secret directly")
        command.add_argument("--date", type=int, help="metadata/signature creation time as Unix epoch seconds")
        command.add_argument("--valid-for-days", type=int, default=30)
    verify = commands.add_parser("verify", help="verify the complete pinned Fedora repository trust chain")
    verify.add_argument("--repository", type=Path, required=True)
    verify.add_argument("--public-key", type=Path, required=True,
                        help="independently trusted ASCII-armored repository key")
    verify.add_argument("--fingerprint", required=True, help="expected uppercase primary fingerprint")
    verify.add_argument("--now", type=int, help="explicit verification time for fixtures or historical snapshots")
    args = parser.parse_args()
    if args.command == "verify":
        manifest = verify_repository(args.repository, args.public_key, args.fingerprint, args.now)
    else:
        manifest = write_candidate(args, rollback=args.command == "rollback")
    print(json.dumps({
        key: manifest[key] for key in
        ("revision", "signingFingerprint", "createdAt", "validUntil", "target", "packages")
    }, sort_keys=True))


if __name__ == "__main__":
    try:
        main()
    except (RepositoryError, ET.ParseError, OSError, ValueError, KeyError, TypeError,
            EOFError, OverflowError, UnicodeError) as error:
        print(f"rpm-repository: {error}", file=sys.stderr)
        sys.exit(1)
