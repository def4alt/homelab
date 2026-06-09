# Remove Longhorn from `perun` while preserving persistent data

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with that file.

## Purpose / Big Picture

After this change, the home cluster on `perun` no longer depends on Longhorn for storage, but the data currently stored on Longhorn-backed PersistentVolumeClaims remains available to the workloads that already use it. The user-visible outcome is that Home Assistant, Pi-hole, Immich, JuiceFS metadata, Minecraft, Grafana, and Prometheus continue to start with their existing data after Longhorn is removed from both GitOps and the host.

The change matters because `perun` is a single-node cluster. Longhorn adds extra moving parts that are more valuable on multi-node stateful clusters. Replacing it with single-node local storage keeps the data on disk while simplifying the home cluster.

## Progress

- [x] (2026-06-03 14:10Z) Audit the current Longhorn footprint on `perun`, including storage classes, bound claims, and host disk headroom.
- [x] (2026-06-03 14:10Z) Identify the repo files that currently force the home cluster to depend on Longhorn.
- [x] (2026-06-03 14:48Z) Complete the `pi-hole` prototype migration: copy data into local claims, restart on the new claims, validate DNS and the web UI path, and prune the old GitOps-managed Longhorn PVCs.
- [x] (2026-06-03 14:24Z) Add the replacement storage layer scaffold to the repo and re-enable k3s local-path support in `perun`'s NixOS config.
- [ ] Migrate application data off Longhorn, one workload at a time, with validation after each cutover (completed: `pi-hole`, Grafana, Home Assistant application state, and Home Assistant DB are on local claims; JuiceFS metadata and Immich DB migrations were attempted but not completed cleanly; remaining: Prometheus, Minecraft cutover, Immich DB finalization, and a safe JuiceFS metadata migration path).
- [x] (2026-06-03 14:55Z) Add Barman ObjectStore and ScheduledBackup coverage for `home-assistant-db` and `juicefs-db` so CNPG migrations have a restore path before cutover.
- [ ] Remove the Flux Longhorn overlays, namespace wiring, and `perun` host tweaks that only exist for Longhorn.
- [ ] Reconcile the home cluster to the new revision and verify that no Longhorn custom resources, pods, storage classes, or mounted volumes remain.
- [x] (2026-06-09 08:55Z) Re-audit the live cluster after the stalled cutover and confirm the remaining Longhorn-backed claims (`minecraft-datadir`, `juicefs-db-1`, `immich-db-1`, and Prometheus) plus the current degraded workloads.
- [x] (2026-06-09 08:55Z) Capture a machine-local safety backup of the live Minecraft Longhorn claim before changing its Helm storage binding. The backup is stored under `.agent/backups/minecraft-manual-20260609-105148/`.
- [x] (2026-06-09 08:59Z) Complete the Minecraft cutover by copying the live Longhorn data into `minecraft-datadir-local`, updating the HelmRelease to mount the local PVC, and preserving the live desired replica state of `0` until an explicit restart is requested.
- [ ] Recover JuiceFS metadata by treating the preserved Longhorn data as the source of truth, restoring it into a clean local CNPG cluster, then repointing the JuiceFS secret and validating that Immich mounts `immich-library-juicefs` again.

## Surprises & Discoveries

- Observation: `perun` still has Longhorn as the default StorageClass, and k3s local storage is explicitly disabled.
  Evidence: `nixos/flake.nix` sets `k3sExtraFlags = [ "--disable local-storage" ];`, and `kubectl get sc` shows `longhorn (default)`.

- Observation: Nearly every remaining stateful home workload still uses Longhorn, not just one or two apps.
  Evidence: `kubectl get pvc,pv -A -o wide` shows Longhorn-backed claims for Home Assistant, Immich DB, Grafana, Prometheus, JuiceFS DB, Minecraft, and Pi-hole.

- Observation: Some database workloads do not currently have an obvious off-node restore path in the repo.
  Evidence: `apps/immich/` has a `ScheduledBackup`, but `apps/home-assistant/` and `apps/juicefs/` only define a CNPG `Cluster` with storage and no scheduled backup manifest.

- Observation: There is enough free disk on `perun` to keep the data locally without Longhorn replication overhead.
  Evidence: `df -h /var/lib` showed about `604G` free on `/dev/nvme0n1p2`; `du -sh /var/lib/longhorn` showed about `57G` in Longhorn data.

- Observation: The safest first GitOps step is to add replacement PVCs alongside the old ones rather than mutating existing PVCs in place.
  Evidence: Changing `spec.storageClassName` on an existing PVC is immutable, so direct in-place Flux edits would fail; the repo scaffold now adds `apps/pi-hole/pvc-local.yaml` and `apps/local-storage/pv-pihole.yaml` without touching the live Longhorn claims yet.

- Observation: `pi-hole` and Grafana can be migrated with new claim names while the old Longhorn claims remain intact until validation is complete.
  Evidence: `pi-hole` now runs on `pihole-etc-local` and `pihole-dnsmasq-local`, and `monitoring-grafana` now runs on `monitoring-grafana-local`; both workloads restarted successfully after a copy pod populated the new claims.

- Observation: The live Minecraft release appears intentionally or manually scaled down, even though the repo still says `replicaCount: 1`.
  Evidence: `kubectl -n minecraft get deployment minecraft -o yaml` showed `replicas: 0`, and the live `HelmRelease` data also showed `replicaCount: 0` during inspection.

- Observation: Home Assistant can be cut over safely by switching the chart from `StatefulSet` mode to `Deployment` mode with an `existingClaim`.
  Evidence: After the repo change, Helm deleted the old StatefulSet, created `deployment.apps/home-assistant`, mounted `home-assistant-config-local`, and `wget http://127.0.0.1:8123/` inside the pod returned `HTTP/1.1 200 OK`.

- Observation: The JuiceFS metadata migration is riskier than the other CNPG cutovers because the mounted filesystem can leave behind stale mount pods and a local CNPG restore can be harder to recover once the metadata service starts flapping.
  Evidence: After switching `juicefs-auth.metaurl` to `juicefs-db-local-rw`, the stale mount pod in `kube-system` blocked remounts, and later `juicefs-db-local-1` entered `CrashLoopBackOff` with `PANIC: could not locate a valid checkpoint record at 0/60002C8`.

- Observation: The Minecraft local PVC scaffold exists and is bound, but it is still empty while the live Longhorn claim contains the real server data.
  Evidence: A backup reader pod copied about `923M` from `minecraft-datadir` into `.agent/backups/minecraft-manual-20260609-105148/longhorn`, while the mounted `minecraft-datadir-local` claim archived to only about `1.5K`.

- Observation: The local Minecraft PVC now contains the copied server data and matches the live Longhorn dataset closely enough for a stopped-server cutover.
  Evidence: A migration pod reported `924.6M` on `/mnt/longhorn` and `922.9M` on `/mnt/local` after `cp -a`, and `cmp -s /mnt/longhorn/server.properties /mnt/local/server.properties` succeeded.

- Observation: The live Helm release for Minecraft is intentionally scaled to zero even though the repository still says `replicaCount: 1`.
  Evidence: `kubectl -n minecraft get helmrelease minecraft -o yaml` showed `spec.values.replicaCount: 0`, while `apps/minecraft/helmrelease.yaml` still declares `replicaCount: 1`.

- Observation: The old Longhorn-backed JuiceFS volume still contains a preserved pre-failure PostgreSQL data directory in addition to the fresh empty initdb directory created during the failed cutover.
  Evidence: `pg_controldata` on `/mnt/data/pgdata_20260603T164229Z` from the `juicefs-db-1` PVC reported a shut down cluster with system identifier `7630368090983460886`, high checkpoint LSN `14/D0000028`, and transaction counters far beyond the fresh empty `pgdata` directory.

## Decision Log

- Decision: Treat this as a staged migration, not an uninstall-first cleanup.
  Rationale: Removing Longhorn before each claim has a verified replacement would destroy the live data path for several applications.
  Date/Author: 2026-06-03 / Codex

- Decision: Migrate the least risky workload first (`pi-hole`) before touching operator-managed or chart-generated database claims.
  Rationale: `pi-hole` uses two plainly declared PVCs in `apps/pi-hole/pvc.yaml`, so it is the safest place to prove the copy-and-cutover procedure.
  Date/Author: 2026-06-03 / Codex

- Decision: Replace Longhorn on `perun` with single-node local storage and remove the Longhorn-specific host settings after the data cutover completes.
  Rationale: `perun` is a single-node home cluster, so local disk is the simplest steady state once the existing data has been copied to stable host paths.
  Date/Author: 2026-06-03 / Codex

- Decision: Use explicit host-backed static PVs for migrated datasets, plus k3s local-path for future dynamic claims.
  Rationale: Static PVs give each migrated dataset a stable host directory and avoid guessing where dynamic provisioners place copied data, while re-enabling local-path keeps the cluster usable after Longhorn is removed.
  Date/Author: 2026-06-03 / Codex

- Decision: For Deployment-based workloads, prefer a new local PVC name over trying to mutate or recycle the original Longhorn PVC in place.
  Rationale: This avoids immutable PVC fields, lets the old Longhorn claim stay available until validation passes, and works cleanly with both `pi-hole` and Grafana.
  Date/Author: 2026-06-03 / Codex

- Decision: Do not cut over Minecraft until its desired replica state is understood and preserved.
  Rationale: The repo says `replicaCount: 1`, but the live cluster is currently at `replicaCount: 0`; forcing a storage cutover before resolving that drift could accidentally start the server.
  Date/Author: 2026-06-03 / Codex

- Decision: Migrate Home Assistant's application state separately from its PostgreSQL database by switching the chart to `Deployment` mode with `persistence.existingClaim`.
  Rationale: The app state claim was small and chart-managed, while the CNPG database claim is a separate higher-risk migration. Splitting them reduces scope and proved the chart can run from a local claim without waiting for the database migration strategy to be finalized.
  Date/Author: 2026-06-03 / Codex

- Decision: Roll back the JuiceFS metadata service cutover in GitOps until a safer recovery path is implemented.
  Rationale: The attempted local-cluster cutover left `juicefs-db-local` unstable and prevented Immich from mounting the JuiceFS volume reliably. Preserving recoverability is more important than forcing that migration through in one pass.
  Date/Author: 2026-06-03 / Codex

- Decision: Keep Minecraft at `replicaCount: 0` during the storage cutover and only switch the backing claim.
  Rationale: The live cluster is intentionally stopped. Preserving that state avoids accidental server startup while still finishing the storage migration and making the repo match the live desired state.
  Date/Author: 2026-06-09 / Codex

- Decision: Use `persistence.dataDir.existingClaim` for Minecraft instead of dynamic provisioning on `manual-local`.
  Rationale: The local PVC already exists and is pre-bound to a stable hostPath PV. Reusing it matches the migration pattern already proven for other single-node workloads and avoids replacing the chart's PVC name in-place.
  Date/Author: 2026-06-09 / Codex

- Decision: Recover JuiceFS metadata from the preserved Longhorn data rather than from the partially initialized local CNPG directory.
  Rationale: The Longhorn claim still contains the last known good metadata directory, while the local copy is the one that later failed recovery and blocked Immich from mounting its media library.
  Date/Author: 2026-06-09 / Codex

## Outcomes & Retrospective

Partial outcome on 2026-06-03: the migration method is proven for multiple workload shapes. `pi-hole` now serves from local claims and its old GitOps-managed Longhorn PVCs have been pruned. Grafana now serves from a local claim and still exposes `grafana.db` from the copied dataset. Home Assistant now runs as a Deployment from `home-assistant-config-local`, and both its app-state PVC and database PVC have been moved off Longhorn. The plan still has major remaining work: Prometheus, Minecraft, Immich DB, and a safe JuiceFS metadata migration path.

Update on 2026-06-09: the cluster re-audit narrowed the remaining Longhorn use to four claims: `minecraft-datadir`, `juicefs-db-1`, `immich-db-1`, and the Prometheus data PVC. The Minecraft cutover can proceed safely now that a machine-local backup exists and the live desired state is confirmed to remain scaled down. The highest-risk remaining item is JuiceFS metadata recovery because Immich availability depends on it.

## Context and Orientation

This repository manages two clusters. The home cluster runs on `perun`; the Hetzner cluster runs on `zorya`. This plan affects only `perun`.

Longhorn is a Kubernetes storage system that creates network-addressed volumes and exposes them through the `longhorn` StorageClass. In this repository, Longhorn is installed by Flux from `apps/longhorn/` and `apps/longhorn-config/`, and the home cluster includes those overlays through `clusters/home/overlays/kustomization.yaml`.

A PersistentVolumeClaim, or PVC, is a Kubernetes object that asks for disk space. A PersistentVolume, or PV, is the disk object that satisfies that request. Today, most home-cluster PVCs are dynamically backed by Longhorn. The replacement design for this plan is single-node local storage on `perun`, meaning Kubernetes will mount directories from `perun`'s own disk instead of asking Longhorn to manage a separate volume layer.

The relevant repository files are:

- `nixos/flake.nix` defines host metadata for `perun`, including `enableLonghornHostTweaks`, `enableOpeniscsi`, and `k3sExtraFlags = [ "--disable local-storage" ]`.
- `nixos/configuration.nix` turns those host metadata flags into actual system services and Longhorn-related host tweaks.
- `clusters/home/overlays/kustomization.yaml` includes `infra/longhorn.yaml` and `infra/longhorn-config.yaml`.
- `clusters/home/overlays/apps/*.yaml` and `clusters/home/overlays/infra/*.yaml` include `dependsOn: longhorn` for workloads that wait on Longhorn.
- `apps/home-assistant/helmrelease.yaml` stores Home Assistant state on Longhorn.
- `apps/home-assistant/postgres-cluster.yaml` stores the Home Assistant database on a Longhorn-backed CloudNativePG PVC.
- `apps/immich/postgres-cluster.yaml` stores the Immich database on Longhorn; the large media library is already on JuiceFS and is not part of this Longhorn migration.
- `apps/juicefs/postgres-cluster.yaml` stores the JuiceFS metadata database on Longhorn.
- `apps/pi-hole/pvc.yaml` declares two direct Longhorn PVCs.
- `apps/minecraft/helmrelease.yaml` stores the Minecraft datadir on Longhorn.
- `apps/monitoring/helmrelease.yaml` stores Grafana and Prometheus data on Longhorn.
- `apps/local-storage/` now contains the migration-time static PV definitions and the `manual-local` StorageClass.
- `apps/namespaces/kustomization.yaml` includes `namespace-longhorn-system.yaml`, which will be removed at the end.

The current live Longhorn-backed claims on `perun` began as:

- `home-assistant/home-assistant-db-1` — 25Gi claim, about 21.6Gi actual Longhorn data.
- `home-assistant/home-assistant-home-assistant-0` — 10Gi claim, about 0.63Gi actual Longhorn data.
- `immich/immich-db-1` — 20Gi claim, about 9.0Gi actual Longhorn data.
- `infra/monitoring-grafana` — 5Gi claim, about 0.43Gi actual Longhorn data.
- `infra/prometheus-monitoring-kube-prometheus-prometheus-db-prometheus-monitoring-kube-prometheus-prometheus-0` — 25Gi claim, about 25.7Gi actual Longhorn data.
- `juicefs/juicefs-db-1` — 10Gi claim, about 0.92Gi actual Longhorn data.
- `minecraft/minecraft-datadir` — 20Gi claim, about 1.68Gi actual Longhorn data.
- `pi-hole/pihole-etc` — 2Gi claim, about 0.60Gi actual Longhorn data.
- `pi-hole/pihole-dnsmasq` — 1Gi claim, about 0.10Gi actual Longhorn data.

Current status update on 2026-06-03:

- `pi-hole` now runs from `pihole-etc-local` and `pihole-dnsmasq-local`; the old Longhorn PVs are retained and released.
- Grafana now runs from `monitoring-grafana-local`; the old `monitoring-grafana` Longhorn PVC is gone.
- Home Assistant now runs from `home-assistant-config-local`; the old `home-assistant-home-assistant-0` Longhorn PVC is gone and its PV is retained/released.
- `minecraft-datadir-local` has been staged but not cut over.

The current non-Longhorn persistent claim that must not be disturbed is:

- `immich/immich-library-juicefs` — 500Gi claim on the `immich-juicefs` StorageClass.

## Plan of Work

The work will proceed in six milestones.

### Milestone 1: Prepare the replacement storage design

Create a dedicated local-storage layer for `perun` in GitOps. The replacement must be explicit enough that a future reader can see where each dataset lives on disk. The preferred design is a new repository area for host-backed PVs, one PV per Longhorn claim being migrated, with stable host paths under a single top-level directory on `perun` such as `/var/lib/k8s-local-storage/<namespace>/<claim>` or `/srv/k8s-local-storage/<namespace>/<claim>`. The exact top-level path must be recorded in this plan once chosen.

At the same time, update `nixos/flake.nix` for `perun` so k3s no longer disables the built-in local storage provisioner. That keeps the home cluster capable of future dynamic local claims after Longhorn is gone, even though the migrated claims themselves should use explicit PVs for predictable paths.

This milestone is complete when the repo contains the new local-storage manifests, `kubectl kustomize clusters/home` renders without Longhorn-specific migration errors, and the `perun` NixOS config is ready to re-enable local-path support.

Status update on 2026-06-03: this milestone is implemented in the working tree through `apps/local-storage/`, `clusters/home/overlays/infra/local-storage.yaml`, and the `nixos/flake.nix` change that removes `--disable local-storage` for `perun`. The render check already passes locally.

### Milestone 2: Prove the migration procedure on `pi-hole`

Use `pi-hole` as the prototype because its PVCs are simple and directly declared in `apps/pi-hole/pvc.yaml`. Add replacement PVs and change the PVC manifests so they bind to those replacement PVs instead of Longhorn after cutover. Then run a controlled copy procedure:

1. Scale the `pi-hole` deployment to zero.
2. Run a copy pod that mounts the old Longhorn claim and the new host path, then uses `rsync -aHAX --delete` or `cp -a` to copy the data.
3. Delete the old Longhorn PVC only after the copied data has been verified.
4. Apply the repo change that binds `pi-hole` back to the replacement PVs.
5. Scale `pi-hole` back up and verify that the web UI, DNS responder, and existing configuration still work.

This milestone is complete when `pi-hole` restarts with the same settings as before, and `kubectl get pvc -n pi-hole` shows replacement non-Longhorn bindings.

### Milestone 3: Migrate Helm and operator managed application claims

Migrate `home-assistant`, `minecraft`, and `monitoring` next. These apps rely on controllers that create or manage PVCs from Helm values. Update the Helm values so they no longer request `storageClass: longhorn`. For each claim, pre-create a matching replacement PV and perform the same stop, copy, cutover, restart, and validate cycle.

Prometheus deserves special care because its claim name is long and its actual data size is currently the largest single Longhorn dataset. Expect the migration copy to take longer. Grafana is low risk because dashboards are mostly GitOps-managed and admin credentials come from an existing secret, but its PVC should still be preserved.

This milestone is complete when `kubectl get pvc -n home-assistant`, `-n minecraft`, and `-n infra` shows no Longhorn-backed PVCs for these workloads, and the apps restart successfully with their existing state.

Status update on 2026-06-03: Grafana and Home Assistant application state have been migrated successfully, while Prometheus and Minecraft still remain on Longhorn or await cutover.

### Milestone 4: Migrate the CloudNativePG database claims

CloudNativePG, often abbreviated CNPG, is the PostgreSQL operator used by `home-assistant`, `immich`, and `juicefs`. An operator is a Kubernetes controller that keeps a higher-level resource, here a `Cluster`, in the desired state. CNPG-managed claims are riskier than direct deployment PVCs because the operator may recreate pods and claims during reconciliation.

Before touching CNPG storage, add or verify a restorable backup path where the repo currently lacks one. `immich` already has a `ScheduledBackup`; `home-assistant` and `juicefs` need explicit backup coverage before their PVCs are cut over. Once that is in place, migrate one CNPG cluster at a time. The exact cutover method must be documented as it is proven. The preferred order is:

1. `juicefs-db` because it is small and isolated.
2. `home-assistant-db` because Home Assistant depends on it, but its data size is known.
3. `immich-db` because it is larger and the app has more moving parts.

If direct PVC recreation under the existing cluster name proves unsafe, create a fresh CNPG cluster on local storage, restore or replicate data into it, switch the consuming app secret or service reference, and only then delete the old Longhorn-backed cluster. Any such change of method must be recorded in the `Decision Log` and reflected throughout this plan.

This milestone is complete when all CNPG PVCs on `perun` are off Longhorn and each consuming app can perform a real read and write operation.

### Milestone 5: Remove Longhorn from GitOps and the host

After every workload is running on replacement storage, remove Longhorn from `clusters/home/overlays/kustomization.yaml`, delete the `dependsOn: longhorn` entries in home overlays, remove `apps/longhorn/` and `apps/longhorn-config/` from the home cluster path, and stop including `namespace-longhorn-system.yaml` from `apps/namespaces/kustomization.yaml`.

Then update `nixos/flake.nix` so `perun` no longer sets `enableLonghornHostTweaks = true` or `enableOpeniscsi = true`. Those settings exist only to support Longhorn. Rebuild `perun` after the Git commit is pushed, in keeping with the user's earlier instruction to commit and push repo changes before rebuilds that depend on them.

This milestone is complete when Flux no longer reconciles Longhorn resources, `kubectl get pods -n longhorn-system` returns no resources, and `systemctl` no longer needs the Longhorn-related host services.

### Milestone 6: Final validation and cleanup

Confirm that the home cluster has exactly the storage systems it should have: local storage for single-node app state, JuiceFS for the Immich media library, and CNPG backups where expected. Delete any leftover Longhorn volumes, CRDs, or StorageClasses only after verifying that no PVC or PV still references them.

This milestone is complete when `kubectl get sc,pv,pvc -A` shows no `longhorn` StorageClass in use, all required apps are healthy, and the repo no longer contains home-cluster Longhorn wiring.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab` unless another directory is stated.

1. Render the home cluster before changes so there is a known-good baseline.

    kubectl kustomize clusters/home >/tmp/home-before-longhorn-removal.yaml

2. Audit the live storage objects on `perun` before each migration round.

    ssh perun@192.168.88.189
    sudo k3s kubectl get sc,pvc,pv -A -o wide
    sudo k3s kubectl -n longhorn-system get volumes.longhorn.io \
      -o custom-columns=NAME:.metadata.name,STATE:.status.state,ROBUSTNESS:.status.robustness,SIZE:.spec.size,ACTUAL:.status.actualSize,NODE:.status.ownerID,FRONTEND:.spec.frontend

3. For the prototype `pi-hole` migration, record the live deployment and current PVC contents before stopping it.

    sudo k3s kubectl -n pi-hole get deploy,pvc,pv,pods
    sudo k3s kubectl -n pi-hole exec deploy/pihole -- ls -la /etc/pihole /etc/dnsmasq.d

4. Apply repo changes in small commits. After each repo edit round, run:

    kubectl kustomize clusters/home >/tmp/home-after-edit.yaml

   and verify it renders successfully.

   Evidence already captured for the scaffold and early migrations:

    $ kubectl kustomize clusters/home >/tmp/home-kustomize.out && echo OK-home
    OK-home

    $ kubectl kustomize apps/pi-hole >/tmp/pihole-kustomize.out && echo OK-pihole
    OK-pihole

    $ kubectl kustomize apps/monitoring >/tmp/monitoring-kustomize.out

5. Before rebuilding `perun`, commit and push the repo revision that contains the new NixOS and GitOps manifests.

    git add <changed files>
    git commit -m "feat(storage): add perun local volume migration"
    git push <remote> main

6. Rebuild `perun` only after the commit is pushed.

    ssh perun@192.168.88.189
    sudo nixos-rebuild switch --flake /path/to/checked-out/homelab/nixos#perun

7. After each application cutover, validate both Kubernetes state and real application behavior. Examples:

    sudo k3s kubectl get pvc,pv -A -o wide
    sudo k3s kubectl get pods -A
    curl -I https://home.def4alt.com
    dig @192.168.88.189 def4alt.com

8. After all migrations, remove Longhorn and reconcile Flux.

    sudo k3s kubectl get kustomizations -A
    sudo k3s kubectl get pods -n longhorn-system
    sudo k3s kubectl get sc,pv,pvc -A -o wide

## Validation and Acceptance

The change is accepted only when all of the following are true:

- `kubectl get sc` on `perun` shows that new claims do not require Longhorn, and no bound claim still references `longhorn`.
- `kubectl get pvc -A -o wide` shows every formerly Longhorn-backed claim rebound to the replacement storage.
- `kubectl get pods -A` shows the home workloads healthy after their individual migrations.
- Home Assistant loads at `https://home.def4alt.com` and retains its prior entities, history database connection, and configuration.
- Pi-hole still answers DNS and retains its prior configuration.
- Immich loads successfully and still reaches both its database and its existing JuiceFS media library.
- Minecraft starts with the same world data.
- Grafana and Prometheus start successfully; if Prometheus historical metrics are intentionally reset instead of preserved, that exception must be approved explicitly and recorded in this plan before execution.
- `kubectl get pods -n longhorn-system` returns no remaining Longhorn pods after final cleanup.
- `kubectl get volumes.longhorn.io -A` and `kubectl get engines.longhorn.io -A` return no remaining Longhorn-managed volumes after final cleanup.

## Idempotence and Recovery

The migration must be done one workload at a time. Do not remove the old Longhorn PVC for a workload until a fresh copy exists on the replacement host path and that copy has been inspected.

Every migration step should be repeatable. Re-running the copy pod is safe if it uses `rsync -aHAX --delete` from the stopped source volume into the destination path. If a cutover fails, stop the workload again, point it back at the old Longhorn claim, and restart it before attempting a second migration.

Do not delete the Longhorn namespace, StorageClass, or host packages until every workload has passed its post-cutover validation. As an extra safety measure, set any Longhorn PVs that are about to be retired to `Retain` before deleting their PVCs so an accidental early delete does not immediately destroy the underlying volume.

## Artifacts and Notes

Initial live audit captured on 2026-06-03:

    $ kubectl get sc
    longhorn (default)
    longhorn-static
    immich-juicefs

    $ kubectl get pvc -A -o wide
    home-assistant/home-assistant-db-1 -> longhorn
    home-assistant/home-assistant-home-assistant-0 -> longhorn
    immich/immich-db-1 -> longhorn
    immich/immich-library-juicefs -> immich-juicefs
    infra/monitoring-grafana -> longhorn
    infra/prometheus-...-0 -> longhorn
    juicefs/juicefs-db-1 -> longhorn
    minecraft/minecraft-datadir -> longhorn
    pi-hole/pihole-etc -> longhorn
    pi-hole/pihole-dnsmasq -> longhorn

    $ kubectl -n longhorn-system get volumes.longhorn.io -o custom-columns=...
    pvc-54ee... actual ~21.6Gi  (home-assistant-db)
    pvc-5e2d... actual ~25.7Gi  (prometheus)
    pvc-5a69... actual ~9.0Gi   (immich-db)
    pvc-d3c9... actual ~0.92Gi  (juicefs-db)
    pvc-f5af... actual ~0.63Gi  (home-assistant config)
    pvc-cb84... actual ~0.60Gi  (pi-hole etc)
    pvc-3152... actual ~0.43Gi  (grafana)
    pvc-46ba... actual ~1.68Gi  (minecraft)
    pvc-6c33... actual ~0.10Gi  (pi-hole dnsmasq)

    $ df -h /var/lib
    /dev/nvme0n1p2  931G size, 324G used, 604G available

    $ du -sh /var/lib/longhorn
    57G /var/lib/longhorn

## Interfaces and Dependencies

This work touches NixOS host configuration, Flux Kustomizations, HelmRelease values, direct PVC manifests, and CloudNativePG cluster manifests.

At the end of the migration, the following interfaces must exist or be updated:

- `nixos/flake.nix` must define `perun` without `--disable local-storage`, and eventually without the Longhorn-only host flags.
- `nixos/configuration.nix` must continue to evaluate cleanly when `enableLonghornHostTweaks` and `enableOpeniscsi` are disabled for `perun`.
- A new repository area must define the replacement PVs for `perun` and must be wired into `clusters/home/overlays/`.
- `apps/pi-hole/pvc.yaml` must bind to the replacement storage instead of `longhorn`.
- `apps/home-assistant/helmrelease.yaml`, `apps/minecraft/helmrelease.yaml`, and `apps/monitoring/helmrelease.yaml` must stop requesting `storageClass: longhorn`.
- `apps/home-assistant/postgres-cluster.yaml`, `apps/immich/postgres-cluster.yaml`, and `apps/juicefs/postgres-cluster.yaml` must no longer rely on Longhorn for future storage provisioning.
- `clusters/home/overlays/kustomization.yaml` and home overlay dependencies must stop referencing Longhorn.

Change note: Initial plan created after auditing the live Longhorn footprint on `perun`, confirming that Longhorn remains the default storage class and that the data can fit on local disk.
