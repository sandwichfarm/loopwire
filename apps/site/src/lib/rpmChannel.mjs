/**
 * RPM repository instructions are advertised only after the complete public
 * verification record for the supported target has been reviewed and committed.
 * Invalid or incomplete records preserve the signed direct-download option.
 * @param {unknown} value
 */
export function verifiedFedoraChannel(value) {
  return verifiedRpmChannel(value, "fedora-44");
}

/** @param {unknown} value */
export function verifiedOpenSuseChannel(value) {
  return verifiedRpmChannel(value, "opensuse-tumbleweed");
}

/** @param {unknown} value @param {string} target */
function verifiedRpmChannel(value, target) {
  if (!value || typeof value !== "object") return null;
  const channel = /** @type {Record<string, unknown>} */ (value);
  if (channel.schemaVersion !== 1 || channel.status !== "verified" || channel.target !== target ||
      typeof channel.baseUrl !== "string" || !validBaseUrl(channel.baseUrl) ||
      typeof channel.signingFingerprint !== "string" || !/^[A-F0-9]{40}$/.test(channel.signingFingerprint) ||
      typeof channel.revision !== "string" || !/^[a-f0-9]{64}$/.test(channel.revision) ||
      typeof channel.verifiedAt !== "string" || !validTimestamp(channel.verifiedAt) ||
      typeof channel.proofUrl !== "string" ||
      !/^https:\/\/github\.com\/sandwichfarm\/loopwire\/actions\/runs\/[1-9][0-9]*$/.test(channel.proofUrl)) {
    return null;
  }
  return {
    target: channel.target,
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
export function fedoraInstallOption(channel, manual) {
  if (!verifiedFedoraChannel(channel)) return manual;
  return {
    ...manual,
    command: "sudo dnf install loopwire",
    note: "After one-time setup, install and update Loopwire through its signed Fedora repository.",
    detail: "Fedora 44 on x86_64 is supported. Other releases and architectures use the portable path.",
    href: "/docs/guide/fedora-repository.html#one-time-setup",
    link: "Set up the Fedora repository"
  };
}

/**
 * @template {{command: string, note: string, detail: string, href: string, link: string}} T
 * @param {unknown} channel
 * @param {T} manual
 * @returns {T}
 */
export function opensuseInstallOption(channel, manual) {
  if (!verifiedOpenSuseChannel(channel)) return manual;
  return {
    ...manual,
    command: "sudo zypper install loopwire",
    note: "After one-time setup, install and update Loopwire through its signed openSUSE repository.",
    detail: "For openSUSE Tumbleweed on x86_64. Check the guide for rolling-release compatibility.",
    href: "/docs/guide/opensuse-repository.html#one-time-setup",
    link: "Set up the openSUSE repository"
  };
}
