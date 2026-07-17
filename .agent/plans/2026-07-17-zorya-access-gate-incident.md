# Contain and recover from the zorya Access Gate incident

## Goal

Contain unauthorized scanning from zorya, preserve evidence, determine the access path and affected credentials, prevent lateral movement to perun, and leave the homelab in a trustworthy state.

## Progress

- [x] (2026-07-17) Confirm the Hetzner report is sequential outbound SSH scanning from zorya.
- [x] (2026-07-17) Identify the live source as `/home/def4alt/.access_gate/.../beam.smp` running as `def4alt`.
- [x] (2026-07-17) Freeze the scanner and record process, socket, environment-key names, file metadata, and executable hashes.
- [x] (2026-07-17) Archive the complete 609 MiB Access Gate directory and supporting journal/process evidence.
- [x] (2026-07-17) Verify artifact checksums after copying evidence to perun.
- [x] (2026-07-17) Kill Access Gate, kill orphaned zorya Kubernetes workloads, block outbound SSH, and restrict inbound SSH to Tailscale.
- [x] (2026-07-17) Quarantine the original Access Gate installation and user service as root-owned files.
- [x] (2026-07-17) Confirm the user does not recognize the successful public login source or Access Gate deployment.
- [x] (2026-07-17) Power off zorya.
- [x] (2026-07-17) Check perun for Access Gate, suspicious outbound SSH, and accepted logins from zorya; none were found.
- [x] (2026-07-17) Disable password/keyboard-interactive/root SSH and change the k3s administrator kubeconfig from `0644` to `0600` on source-controlled hosts; rebuild and verify perun.
- [x] (2026-07-17) Replace Flux's compromised HTTPS PAT dependency with a repository-scoped, read-only SSH deploy key (`208c847`).
- [x] (2026-07-17) Generate a new SOPS Age identity, re-encrypt and verify all 18 SOPS files, deploy the new identity to Flux, and remove the old identities from perun and the operator workstation (`e7a939a`).
- [ ] Rotate/revoke every remaining credential that was readable from zorya, beginning with Tailscale, the old GitHub PAT, Cloudflare, backup storage, Authentik, application secrets, and the shared password.
- [x] (2026-07-17) Audit perun host authentication, processes, files, persistence, connections, Kubernetes RBAC, recent pods/secrets, and privileged/host-mounted workloads; no evidence of lateral movement was found. Remove five stale node-debugger pods after review.
- [ ] Reinstall or delete zorya; do not trust or return the existing filesystem to service.
- [ ] Submit a concise incident response to Hetzner with containment time and root cause.

## Confirmed evidence

- The abusive process started at `2026-07-16 07:11:38 UTC` from an SSH session whose environment recorded source `91.151.136.237`.
- The journal contains repeated successful password authentication as `def4alt` from `91.151.136.237` beginning at `07:10:48 UTC`. The user confirms this was not their access; their legitimate zorya access was through Tailscale.
- Access Gate advertised explicit `netscan`, `scanner`, `ssh_scan`, and `ssh_brute` capabilities. Its log records API actions including `scans/start_scan`, `ssh_scan/start_shard`, and many `ssh_brute/start_shard` calls.
- Live sockets from the Access Gate Erlang VM included many outbound TCP/22 connections and SYNs, matching Hetzner's report.
- Access Gate ran as `def4alt`, whose environment exposed a world-readable administrator kubeconfig path plus paths to the SOPS Age key and API-key files. Because the attacker knew the shared account/sudo password, assume root-level access and compromise of every secret available on zorya.
- The evidence archive is stored on perun at `/var/lib/k8s-migration/zorya-incident-20260717`, root-owned mode `0600`, with passing SHA-256 verification. A root-owned quarantine copy remains on zorya's powered-off disk.
- Perun has no Access Gate files/process, no suspicious outbound SSH connections, and no accepted SSH sessions from zorya's Tailscale address in the reviewed journal.

## Decisions

- Treat this as a confirmed account compromise, not an accidental user scan.
- Do not restart zorya. Preserve a Hetzner disk snapshot before deletion if more forensic work is required.
- Treat credentials as compromised even without direct proof of exfiltration; the attacker had both account access and paths/permissions sufficient to retrieve them.
- Prefer key-only SSH immediately. Password rotation alone is insufficient.
- Do not copy executable content from zorya back into production. The migrated application databases/data require application-level review and credential rotation, but the zorya host filesystem is not trusted.

## Required rotations

1. Revoke zorya in the Tailscale admin console and expire any reusable auth keys.
2. **Partially complete:** Flux now uses a new read-only SSH deploy key. Revoke the old GitHub PAT and inspect account/repository audit logs in GitHub.
3. **Complete:** Flux and all current encrypted files now use only the new SOPS Age identity.
4. Rotate the Cloudflare API token, tunnel token, and any origin credentials.
5. Rotate B2/S3/CNPG/Restic credentials and inspect provider access logs.
6. Rotate Authentik secret material, outpost tokens, recovery/session credentials, and admin password; invalidate sessions.
7. Rotate application database/password/API/webhook/Telegram credentials stored in SOPS.
8. Change the shared NixOS user password after key-only SSH is confirmed.

## Hetzner response evidence

State that an unauthorized process under the compromised `def4alt` account initiated SSH scanning, the process was stopped and preserved, outbound SSH was blocked, public SSH was closed, all zorya workloads were terminated, and the server was powered off on 2026-07-17. State that zorya will not return to service without reinstall/replacement and affected credentials are being rotated.

Suggested response:

> We investigated the reported outbound TCP/22 activity from `46.62.137.102` and confirmed that an unauthorized process running under a compromised user account initiated SSH scanning. We stopped and preserved the process and supporting logs, blocked outbound SSH, closed public SSH access, terminated the server's workloads, and powered the server off on 17 July 2026. The affected server will not be returned to service from its current installation; it will be replaced or reinstalled from trusted media. We have also disabled password-based SSH and are rotating all credentials that may have been accessible from the host. The reported activity has been contained.
