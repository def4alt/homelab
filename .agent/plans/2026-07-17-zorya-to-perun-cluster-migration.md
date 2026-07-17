# Migrate zorya workloads to perun

## Goal

Move every application currently owned by the independent zorya k3s cluster to the existing perun k3s cluster, preserve application state, switch public traffic to perun, verify service health, and retire k3s on zorya only after rollback is no longer needed.

The migrated application set is Blog, Authentik, Glance, and Paperless. Stateful data includes the Authentik PostgreSQL database, Paperless PostgreSQL database and media/data PVC, and Glance data PVC.

## Progress

- [x] (2026-07-17) Confirm migration means moving all zorya workloads to perun rather than joining nodes or relocating only the control plane.
- [x] (2026-07-17) Confirm downtime is acceptable after backups are created and validated.
- [x] (2026-07-17) Confirm the existing Cloudflare edits and removal of the checked-in home Flux components are intended migration work.
- [x] (2026-07-17) Verify zorya's changed SSH host key through the user and replace the stale local known-host entry.
- [x] (2026-07-17) Inventory both live clusters and their stateful resources.
- [ ] Measure source data and identify exact host paths and backup/restore commands.
- [ ] Add perun local PVs and GitOps placement for all four applications; remove obsolete cross-cluster forward-auth topology.
- [ ] Render and validate the repository changes, commit, and push them.
- [ ] Create and verify pre-cutover backups without disrupting source workloads.
- [ ] Suspend zorya Flux, stop writers, take final consistent database dumps/data copies, and restore them on perun.
- [ ] Reconcile perun and verify databases, pods, ingress, authentication, and application data.
- [ ] Switch Cloudflare traffic to perun and verify all public hostnames externally.
- [ ] Keep zorya stopped but intact for rollback, then disable its k3s service after final verification.
- [ ] Update repository documentation and record completion evidence here.

## Discoveries

- zorya and perun are separate single-node k3s clusters, not members of one cluster.
- zorya is healthy at k3s `v1.35.5+k3s1`; perun is healthy at `v1.35.4+k3s1`.
- zorya state consists of four bound local-path PVCs: Authentik DB 5 GiB, Glance 2 GiB, Paperless DB 25 GiB, and Paperless storage 20 GiB.
- zorya has healthy single-instance CloudNativePG clusters named `authentik-db` and `paperless-db`.
- perun has about 172 GiB free on `/` and `/srv`, enough for the requested source PVC capacities, subject to checking actual data and migration workspace requirements.
- perun already runs the home Authentik outpost while the Authentik server/database is on zorya. The steady state can simplify this to in-cluster Authentik and an in-cluster forward-auth endpoint.
- The home overlay already contains dormant definitions for Blog, Authentik, Glance, and Paperless, but they are not listed by `clusters/home/overlays/kustomization.yaml` and some are stale: Paperless depends on removed Longhorn, and base Glance/Paperless PVCs request Longhorn.
- Hetzner mode patches those PVCs to `local-path`. The perun steady state should use explicit host-backed PVs with `Retain`, following existing `apps/local-storage` conventions.
- The working tree began with edits to `cloudflare/dns.tf`, `cloudflare/locals.tf`, and deletion of `clusters/home/flux-system/gotk-components.yaml`. These must be incorporated rather than overwritten.

## Decisions

- Preserve the independent perun cluster identity. Migrate workloads and data, not `/var/lib/rancher/k3s` control-plane state.
- Use logical PostgreSQL dumps/restores for Authentik and Paperless rather than copying CNPG data directories between clusters.
- Use explicit retained host-backed PVs under perun's existing local-storage root for Glance and Paperless application data.
- Keep zorya available as a rollback source until every public service and authentication flow has passed validation.
- Suspend Flux before stopping source workloads so reconciliation cannot restart writers during the final copy.
- Do not expose Kubernetes Secrets or decrypted SOPS material in logs or plan documentation.

## Cutover and rollback

Before cutover, create logical dumps of both databases and copies of Glance and Paperless PVC contents, record sizes/checksums, and confirm the artifacts exist on perun. During cutover, suspend zorya application reconciliation, scale source writers down, take final dumps/copies, then start the restored workloads on perun. Change traffic only after local ingress tests pass.

If validation fails, stop the corresponding perun workload, restore Cloudflare traffic to zorya, resume zorya Flux/app replicas, and diagnose without modifying the preserved source volumes. Do not uninstall k3s or delete zorya PVCs during the rollback window.

## Validation evidence required

- `kubectl kustomize clusters/home` renders successfully.
- Perun Flux Kustomizations for Blog, Authentik, Glance, and Paperless report Ready at the pushed revision.
- Both restored CNPG clusters report healthy with one ready instance.
- Row/data sanity checks succeed for both databases; Glance and Paperless storage checksums/file counts match the source artifacts.
- `def4alt.com`, `auth.def4alt.com`, `dashboard.def4alt.com`, and `papers.def4alt.com` return expected responses through the new origin.
- A real Authentik login and one protected home-app forward-auth flow succeed.
- Paperless can display an existing document and Glance retains its state/configuration.
- zorya application writers remain stopped and its retained data remains available until rollback is explicitly closed.
