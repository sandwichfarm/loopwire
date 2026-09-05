import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { fedoraInstallOption, verifiedFedoraChannel } from "./rpmChannel.mjs";

const verified = {
  schemaVersion: 1,
  status: "verified",
  target: "fedora-44",
  baseUrl: "https://packages.example.test/fedora/44/x86_64/",
  signingFingerprint: "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
  revision: "a".repeat(64),
  verifiedAt: "2026-09-05T10:20:30+00:00",
  proofUrl: "https://github.com/sandwichfarm/loopwire/actions/runs/123456"
};
const manual = {
  id: "fedora",
  command: "sudo dnf --setopt=localpkg_gpgcheck=0 install ./loopwire-0.1.0-1.fc44.x86_64.rpm",
  note: "Verify the signed download first.",
  detail: "Other versions use portable installation.",
  href: "/docs/guide/fedora-repository.html",
  link: "Fedora repository setup and availability"
};

test("pending and incomplete channel records preserve the functional manual option", () => {
  for (const value of [null, undefined, {}, [], { ...verified, status: "pending" }]) {
    assert.equal(verifiedFedoraChannel(value), null);
    assert.equal(fedoraInstallOption(value, manual), manual);
  }
  for (const key of Object.keys(verified)) {
    const value = { ...verified };
    delete value[key];
    assert.equal(verifiedFedoraChannel(value), null, `missing ${key}`);
    assert.equal(fedoraInstallOption(value, manual), manual);
  }
});

test("verified Fedora 44 channel exposes installation and separate setup guidance", () => {
  const channel = verifiedFedoraChannel(verified);
  assert.equal(channel.target, "fedora-44");
  assert.equal(channel.baseUrl, "https://packages.example.test/fedora/44/x86_64");
  const option = fedoraInstallOption(verified, manual);
  assert.equal(option.id, "fedora");
  assert.equal(option.command, "sudo dnf install loopwire");
  assert.equal(option.href, "/docs/guide/fedora-repository.html#one-time-setup");
  assert.doesNotMatch(`${option.note} ${option.detail}`, /workflow|revision|activation|operator/);
  assert.match(manual.command, /localpkg_gpgcheck=0/);
});

test("malformed or wrong-target records never activate the channel", () => {
  const invalid = {
    schemaVersion: [0, "1"], status: [true, "ready"], target: ["fedora-43", "Fedora-44", null],
    baseUrl: ["http://packages.example.test", "https://user:password@packages.example.test", "https://packages.example.test?a=1",
      "https://packages.example.test#fragment", " https://packages.example.test", "https://packages.example.test/\n", "not a URL",
      "https://packages.example.test:0", "https://packages.example.test:65536",
      "https://packages.example.test?", "https://packages.example.test#",
      "https://packages.example.test/$(id)", "https://packages.example.test/`id`", "https://packages.example.test/\\wrong"],
    signingFingerprint: ["a".repeat(40), "A".repeat(39), "G".repeat(40)],
    revision: ["A".repeat(64), "a".repeat(63)],
    verifiedAt: ["yesterday", "2026-09-05", "2026-02-30T00:00:00Z", "2026-09-05T25:00:00Z"],
    proofUrl: ["https://github.com/other/repo/actions/runs/123", "https://github.com/sandwichfarm/loopwire/pull/36",
      "https://github.com/sandwichfarm/loopwire/actions/runs/123?fixture=1", "https://github.com/sandwichfarm/loopwire/actions/runs/0"]
  };
  for (const [key, values] of Object.entries(invalid)) {
    for (const value of values) {
      const record = { ...verified, [key]: value };
      assert.equal(verifiedFedoraChannel(record), null, `${key}: ${value}`);
      assert.equal(fedoraInstallOption(record, manual), manual);
    }
  }
});

test("checked-in Fedora channel remains pending or has a complete verification record", () => {
  const channel = JSON.parse(readFileSync(new URL("../../../../packaging/repositories/fedora-channel.json", import.meta.url), "utf8"));
  if (channel.status === "pending") {
    assert.deepEqual(channel, { schemaVersion: 1, status: "pending", target: null, baseUrl: null,
      signingFingerprint: null, revision: null, verifiedAt: null, proofUrl: null });
  } else {
    assert.ok(verifiedFedoraChannel(channel));
  }
});
