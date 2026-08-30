# Native package VM proof

This review snapshot was promoted only after the full raw proof verifier passed for all four targets.

- Tested commit: `70eee4ec433bb7d967931357cf77bd0c28056a35`
- Raw proof location: ignored `.vm/native-packages/evidence/<target>/70eee4ec433bb7d967931357cf77bd0c28056a35/`
- Full verifier: `pnpm verify:native-vm-proof -- --git-head 70eee4ec433bb7d967931357cf77bd0c28056a35`
- Snapshot verifier: `node scripts/verify-native-package-proof-snapshot.mjs`

The snapshot deliberately excludes VM disks, SSH state, package binaries, serial consoles, and full package-manager
transcripts. Every target directory retains the official image URL/digest, package filename/digest, guest OS and KVM
identity, installed metadata/files, packaged command output, ELF linkage, X11 application-window proof, and uninstall
result. Package binaries are reproducibly rebuilt from the canonical release tarball and are not committed.
