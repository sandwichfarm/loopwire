import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fedoraInstallOption, opensuseInstallOption, verifiedFedoraChannel, verifiedOpenSuseChannel } from "./rpmChannel.mjs";

const verified = {
  schemaVersion: 1, status: "verified", target: "opensuse-tumbleweed",
  baseUrl: "https://packages.example.test/opensuse/tumbleweed/x86_64/",
  signingFingerprint: "ABCDEF0123456789ABCDEF0123456789ABCDEF01", revision: "a".repeat(64),
  verifiedAt: "2026-09-05T10:20:30+00:00",
  proofUrl: "https://github.com/sandwichfarm/loopwire/actions/runs/123456"
};
const manual = {
  id: "opensuse", command: "sudo zypper install --allow-unsigned-rpm ./loopwire-0.1.0-1.x86_64.rpm",
  note: "Authenticate the signed release checksum before installing this local RPM.",
  detail: "Use the matching portable path on other targets.",
  href: "/docs/guide/opensuse-repository.html", link: "openSUSE repository setup and availability"
};

test("pending or incomplete openSUSE records retain the authenticated direct-RPM fallback", () => {
  for (const record of [null, undefined, {}, [], { ...verified, status: "pending" }]) {
    assert.equal(verifiedOpenSuseChannel(record), null);
    assert.equal(opensuseInstallOption(record, manual), manual);
  }
  for (const key of Object.keys(verified)) {
    const record = { ...verified };
    delete record[key];
    assert.equal(verifiedOpenSuseChannel(record), null, `missing ${key}`);
    assert.equal(opensuseInstallOption(record, manual), manual);
  }
});

test("verified openSUSE fixture exposes normal Zypper install and a separate setup link", () => {
  assert.equal(verifiedOpenSuseChannel(verified).baseUrl, "https://packages.example.test/opensuse/tumbleweed/x86_64");
  const option = opensuseInstallOption(verified, manual);
  assert.equal(option.id, "opensuse");
  assert.equal(option.command, "sudo zypper install loopwire");
  assert.equal(option.href, "/docs/guide/opensuse-repository.html#one-time-setup");
  assert.doesNotMatch(`${option.note} ${option.detail}`, /workflow|revision|activation|operator/);
  assert.match(manual.command, /--allow-unsigned-rpm/);
});

test("Fedora and openSUSE verification records cannot activate each other's install option", () => {
  const fedora = { ...verified, target: "fedora-44" };
  assert.ok(verifiedFedoraChannel(fedora));
  assert.equal(verifiedFedoraChannel(verified), null);
  assert.equal(verifiedOpenSuseChannel(fedora), null);
  assert.equal(fedoraInstallOption(verified, manual), manual);
  assert.equal(opensuseInstallOption(fedora, manual), manual);
});

test("malformed or unsupported openSUSE proof records never activate repository instructions", () => {
  const invalid = {
    schemaVersion: [0, "1"], status: [true, "ready"],
    target: ["opensuse-leap", "opensuse-tumbleweed-aarch64", "opensuse-tumbleweed-x86_64", null],
    baseUrl: ["http://packages.example.test", "https://user:pass@packages.example.test", "not a URL",
      "https://packages.example.test?", "https://packages.example.test#", "https://packages.example.test?q=1",
      "https://packages.example.test:0", "https://packages.example.test:65536", " https://packages.example.test",
      "https://packages.example.test/\n", "https://packages.example.test/$(id)", "https://packages.example.test/'"],
    signingFingerprint: ["a".repeat(40), "A".repeat(39), "G".repeat(40)],
    revision: ["A".repeat(64), "a".repeat(63)],
    verifiedAt: ["yesterday", "2026-09-05", "2026-02-30T00:00:00Z", "2026-09-05T25:00:00Z"],
    proofUrl: ["https://github.com/other/repo/actions/runs/123", "https://github.com/sandwichfarm/loopwire/pull/37",
      "https://github.com/sandwichfarm/loopwire/actions/runs/123?fixture=1"]
  };
  for (const [key, values] of Object.entries(invalid)) {
    for (const value of values) {
      const record = { ...verified, [key]: value };
      assert.equal(verifiedOpenSuseChannel(record), null, `${key}: ${value}`);
      assert.equal(opensuseInstallOption(record, manual), manual);
    }
  }
});

test("checked-in openSUSE channel remains pending or has a complete verification record", () => {
  const channel = JSON.parse(readFileSync(new URL("../../../../packaging/repositories/opensuse-channel.json", import.meta.url), "utf8"));
  if (channel.status === "pending") {
    assert.deepEqual(channel, { schemaVersion: 1, status: "pending", target: null, baseUrl: null,
      signingFingerprint: null, revision: null, verifiedAt: null, proofUrl: null });
  } else {
    assert.ok(verifiedOpenSuseChannel(channel));
  }
});
