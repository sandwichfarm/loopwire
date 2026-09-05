#!/usr/bin/env python3
"""Verify a served openSUSE repository before producing its website activation record."""
import argparse
from datetime import datetime, timezone
import hashlib
import json
from pathlib import Path
import re
import ssl
import subprocess
import sys
import tempfile
import urllib.error
import urllib.parse
import urllib.request


TARGET = {"distribution": "opensuse", "release": "tumbleweed", "architecture": "x86_64"}
TARGET_SELECTOR = "opensuse-tumbleweed-x86_64"


class NoRedirects(urllib.request.HTTPRedirectHandler):
    def redirect_request(self, request, response, code, message, headers, new_url):
        response.close()
        raise ValueError("repository verification does not follow redirects; use the canonical HTTPS URL")


def validate_base_url(value):
    url = urllib.parse.urlsplit(value)
    if (url.scheme != "https" or not url.hostname or url.username or url.password
            or any(char in value for char in "\\'\"`$<>?#")
            or any(ord(char) <= 32 or ord(char) >= 127 for char in value)):
        raise ValueError("base URL must be HTTPS without credentials, whitespace, query, fragment, or shell metacharacters")
    if url.port is not None and not 1 <= url.port <= 65535:
        raise ValueError("invalid HTTPS port in base URL")
    return value.rstrip("/")


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--repository", required=True, type=Path)
    parser.add_argument("--public-key", required=True, type=Path)
    parser.add_argument("--fingerprint", required=True)
    parser.add_argument("--base-url", required=True)
    parser.add_argument("--ca-file", type=Path, help="custom CA for isolated test servers")
    parser.add_argument("--proof-url", help="GitHub Actions run URL required for --output")
    parser.add_argument("--output", type=Path, help="write verified channel configuration after all checks")
    args = parser.parse_args()
    base_url = validate_base_url(args.base_url)
    if args.output and args.ca_file:
        raise ValueError("custom-CA fixture checks cannot produce public activation records")
    if args.output and (not args.proof_url or not re.fullmatch(
            r"https://github\.com/sandwichfarm/loopwire/actions/runs/[1-9][0-9]*", args.proof_url)):
        raise ValueError("activation output requires the verifying project GitHub Actions run URL")
    fingerprint = args.fingerprint.upper()
    if not re.fullmatch(r"[A-F0-9]{40}", fingerprint):
        raise ValueError("a complete OpenPGP fingerprint is required")
    subprocess.run([
        sys.executable, str(Path(__file__).with_name("rpm-repository.py")), "verify",
        "--target", TARGET_SELECTOR, "--repository", str(args.repository),
        "--public-key", str(args.public_key), "--fingerprint", fingerprint,
    ], check=True, stdout=subprocess.PIPE)
    manifest_path = args.repository / "repository-manifest.json"
    manifest = json.loads(manifest_path.read_text())
    if manifest.get("target") != TARGET:
        raise ValueError("candidate does not target openSUSE Tumbleweed x86_64")
    manifest_bytes = manifest_path.read_bytes()
    entries = [*manifest["files"], {
        "path": "repository-manifest.json", "size": len(manifest_bytes),
        "sha256": hashlib.sha256(manifest_bytes).hexdigest(),
    }]
    context = ssl.create_default_context(cafile=str(args.ca_file) if args.ca_file else None)
    opener = urllib.request.build_opener(NoRedirects(), urllib.request.HTTPSHandler(context=context))
    for entry in entries:
        url = base_url + "/" + urllib.parse.quote(entry["path"], safe="/+")
        request = urllib.request.Request(url, headers={
            "Cache-Control": "no-cache", "User-Agent": "Loopwire-openSUSE-Proof/1"})
        try:
            response = opener.open(request, timeout=30)
        except urllib.error.HTTPError as error:
            status = error.code
            error.close()
            raise ValueError(f"repository returned HTTP {status} for {entry['path']}") from None
        digest, size = hashlib.sha256(), 0
        with response:
            while chunk := response.read(1024 * 1024):
                size += len(chunk)
                if size > entry["size"]:
                    raise ValueError(f"public file is larger than expected: {entry['path']}")
                digest.update(chunk)
        if size != entry["size"] or digest.hexdigest() != entry["sha256"]:
            raise ValueError(f"public file differs from the verified candidate: {entry['path']}")
    record = {
        "schemaVersion": 1, "status": "verified", "target": "opensuse-tumbleweed",
        "baseUrl": base_url, "signingFingerprint": fingerprint, "revision": manifest["revision"],
        "verifiedAt": datetime.now(timezone.utc).isoformat().replace("+00:00", "Z"), "proofUrl": args.proof_url,
    }
    if args.output:
        args.output.parent.mkdir(parents=True, exist_ok=True)
        with tempfile.NamedTemporaryFile(mode="w", dir=args.output.parent, delete=False) as temporary:
            json.dump(record, temporary, indent=2)
            temporary.write("\n")
            temporary_path = Path(temporary.name)
        temporary_path.replace(args.output)
    print(json.dumps({"status": "verified", "revision": manifest["revision"], "files": len(entries)}))


if __name__ == "__main__":
    try:
        main()
    except (OSError, ValueError, KeyError, subprocess.CalledProcessError, urllib.error.URLError) as error:
        print(f"verify-opensuse-public: {error}", file=sys.stderr)
        sys.exit(1)
