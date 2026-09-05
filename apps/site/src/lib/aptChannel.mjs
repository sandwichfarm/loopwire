/**
 * A public channel is advertised only after its complete HTTPS verification record
 * has been reviewed and committed. Invalid or incomplete records keep manual installs.
 * @param {unknown} value
 */
export function verifiedAptChannel(value) {
  if (!value || typeof value !== "object") return null;
  const channel = /** @type {Record<string, unknown>} */ (value);
  if (channel.schemaVersion !== 1 || channel.status !== "verified" ||
      typeof channel.baseUrl !== "string" || !validBaseUrl(channel.baseUrl) ||
      typeof channel.signingFingerprint !== "string" || !/^[A-F0-9]{40}$/.test(channel.signingFingerprint) ||
      typeof channel.revision !== "string" || !/^[a-f0-9]{64}$/.test(channel.revision) ||
      typeof channel.verifiedAt !== "string" || !validTimestamp(channel.verifiedAt) ||
      typeof channel.proofUrl !== "string" ||
      !/^https:\/\/github\.com\/sandwichfarm\/loopwire\/actions\/runs\/[1-9][0-9]*$/.test(channel.proofUrl)) {
    return null;
  }
  return {
    baseUrl: channel.baseUrl.replace(/\/+$/, ""),
    signingFingerprint: channel.signingFingerprint,
    revision: channel.revision,
    verifiedAt: channel.verifiedAt,
    proofUrl: channel.proofUrl
  };
}

/** @param {string} value */
function validBaseUrl(value) {
  try {
    const url = new URL(value);
    return value.startsWith("https://") && !/[^\x21-\x7e]|[\\'"`$<>?#]/.test(value) &&
      url.protocol === "https:" && Boolean(url.hostname) && !url.username && !url.password &&
      (!url.port || Number(url.port) >= 1) && !url.search && !url.hash;
  } catch {
    return false;
  }
}

/** @param {string} value */
function validTimestamp(value) {
  if (!/^\d{4}-\d{2}-\d{2}T\d{2}:\d{2}:\d{2}(?:\.\d{1,6})?(?:Z|[+-]\d{2}:\d{2})$/.test(value) ||
      !Number.isFinite(Date.parse(value))) return false;
  const date = value.slice(0, 10);
  return new Date(`${date}T00:00:00Z`).toISOString().slice(0, 10) === date;
}

/**
 * @template {{command: string, note: string, detail: string, href: string, link: string}} T
 * @param {unknown} channel
 * @param {T} manual
 * @returns {T}
 */
export function aptInstallOption(channel, manual) {
  if (!verifiedAptChannel(channel)) return manual;
  return {
    ...manual,
    command: "sudo apt install loopwire",
    note: "After one-time setup, install and update Loopwire through its signed APT repository.",
    detail: "Ubuntu 24.04 and Debian 13 on x86_64 are supported. Other versions and ARM64 use the portable path.",
    href: "/docs/guide/apt-repository.html#one-time-setup",
    link: "Set up the APT repository"
  };
}
