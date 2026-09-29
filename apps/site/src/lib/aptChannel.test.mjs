import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import test from "node:test";
import { aptInstallOption, verifiedAptChannel } from "./aptChannel.mjs";

const verified = {
  schemaVersion: 1,
  status: "verified",
  baseUrl: "https://packages.example.test/loopwire/",
  signingFingerprint: "ABCDEF0123456789ABCDEF0123456789ABCDEF01",
  revision: "a".repeat(64),
  verifiedAt: "2026-09-05T10:20:30+00:00",
  proofUrl: "https://github.com/sandwichfarm/loopwire/actions/runs/123456"
};
const manual = {
  id: "ubuntu",
  command: "sudo apt install ./loopwire_0.1.0-1ubuntu24.04_amd64.deb",
  note: "Verify the signed download first.",
  detail: "Other versions use portable installation.",
  href: "/docs/guide/apt-repository.html",
  link: "APT repository setup and availability"
};

test("pending and incomplete channel records preserve the functional manual option", () => {
  for (const value of [null, undefined, {}, [], { ...verified, status: "pending" }]) {
    assert.equal(verifiedAptChannel(value), null);
    assert.equal(aptInstallOption(value, manual), manual);
  }
  for (const key of Object.keys(verified)) {
    const value = { ...verified };
    delete value[key];
    assert.equal(verifiedAptChannel(value), null, `missing ${key}`);
    assert.equal(aptInstallOption(value, manual), manual);
  }
});

test("verified channel exposes an install command and separate one-time setup link", () => {
  assert.equal(verifiedAptChannel(verified).baseUrl, "https://packages.example.test/loopwire");
  for (const id of ["ubuntu", "debian"]) {
    const option = aptInstallOption(verified, { ...manual, id });
    assert.equal(option.id, id);
    assert.equal(option.command, "sudo apt install loopwire");
    assert.equal(option.href, "/docs/guide/apt-repository.html#one-time-setup");
    assert.doesNotMatch(`${option.note} ${option.detail}`, /workflow|revision|activation|operator/);
  }
  assert.match(manual.command, /\.deb$/);
});

test("malformed proof records never activate the channel", () => {
  const invalid = {
    schemaVersion: [0, "1"], status: [true, "ready"],
    baseUrl: ["http://packages.example.test", "https://user:password@packages.example.test", "https://packages.example.test?a=1",
      "https://packages.example.test#fragment", " https://packages.example.test", "https://packages.example.test/\n", "not a URL",
      "https://packages.example.test:0", "https://packages.example.test:65536",
      "https://packages.example.test?", "https://packages.example.test#",
      "https://packages.example.test/$(id)", "https://packages.example.test/`id`", "https://packages.example.test/\\wrong"],
    signingFingerprint: ["a".repeat(40), "A".repeat(39), "G".repeat(40)],
    revision: ["A".repeat(64), "a".repeat(63)],
    verifiedAt: ["yesterday", "2026-09-05", "2026-02-30T00:00:00Z", "2026-09-05T25:00:00Z"],
    proofUrl: ["https://github.com/other/repo/actions/runs/123", "https://github.com/sandwichfarm/loopwire/pull/35",
      "https://github.com/sandwichfarm/loopwire/actions/runs/123?fixture=1", "https://github.com/sandwichfarm/loopwire/actions/runs/0"]
  };
  for (const [key, values] of Object.entries(invalid)) {
    for (const value of values) {
      const record = { ...verified, [key]: value };
      assert.equal(verifiedAptChannel(record), null, `${key}: ${value}`);
      assert.equal(aptInstallOption(record, manual), manual);
    }
  }
});

test("checked-in channel either remains pending or has a complete verification record", () => {
  const channel = JSON.parse(readFileSync(new URL("../../../../packaging/repositories/apt-channel.json", import.meta.url), "utf8"));
  if (channel.status === "pending") {
    assert.deepEqual(channel, { schemaVersion: 1, status: "pending", baseUrl: null,
      signingFingerprint: null, revision: null, verifiedAt: null, proofUrl: null });
  } else {
    assert.ok(verifiedAptChannel(channel));
  }
});
