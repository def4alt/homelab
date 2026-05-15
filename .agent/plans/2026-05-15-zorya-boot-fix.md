# Zorya Boot Fix ExecPlan

**Goal:** Make `zorya` boot reliably on Hetzner after `nixos-anywhere` installs.

**Root cause:** The host config imports `disko`, `sops-nix`, and `home-manager`, but no hardware profile. On this VPS the root disk is exposed through QEMU/virtio-scsi + AHCI. Without initrd storage modules, boot waits on `/dev/disk/by-partlabel/disk-main-root` because the underlying block device never appears early enough.

**Plan:**
1. Add a host-specific hardware module for `zorya`.
2. Import the QEMU guest profile.
3. Pin the initrd storage modules needed by this VPS.
4. Reinstall with `nixos-anywhere`.
5. Verify boot, then follow up on first-boot `sops-nix` key provisioning separately.

**Progress:**
- 2026-05-15: Identified missing hardware config as the likely cause after repeated partlabel boot failures.
- 2026-05-15: Identified unstable `/dev/sdX` ordering between rescue/installer boots. Switched `zorya` disko devices to stable `/dev/disk/by-id/*` paths so the OS disk is always the 76.3G QEMU disk and the data disk is always the 20G Hetzner volume.
- 2026-05-15: Added a direct `hashedPassword` for `def4alt` in the NixOS config instead of using `sops-nix`, because fresh installs do not yet have the age key available during first activation.
