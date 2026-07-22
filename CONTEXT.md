# Homelab Handoff Context

## Current State

The homelab is a single-node NixOS and k3s cluster on `perun`, managed through
FluxCD from this repository. The active home cluster configuration is under
`clusters/home`; application and infrastructure manifests are under `apps`.

The most recent deployed Git revision is `6c13fd0`. The repository was clean
before this handoff file was created. `CONTEXT.md` is intentionally untracked and
must not be committed unless explicitly requested later.

## Architecture

- Host: `perun`, NixOS, x86_64 Linux
- Kubernetes: single-node k3s
- Delivery: FluxCD reconciles `main`
- Ingress: Traefik
- Certificates: cert-manager
- Public routing: Cloudflare Tunnel
- Databases: CloudNativePG
- Local persistent storage: statically bound `manual-local` volumes
- Shared application storage: JuiceFS where required
- NixOS source: `nixos/flake.nix`
- Only NixOS output: `nixosConfigurations.perun`

The old `zorya` NixOS configuration was removed. The decommissioned
`clusters/hetzner` Flux structure remains in the repository, but it is separate
from the NixOS host definitions.

## Active Observability Stack

The intentionally small observability stack is:

- kube-prometheus-stack
- Prometheus
- Alertmanager
- Grafana
- Loki in single-binary mode
- Grafana Alloy as a DaemonSet
- Prometheus Blackbox Exporter

Beszel and Uptime Kuma were removed because Prometheus, Grafana, and Blackbox
Exporter already cover their required monitoring functions. Dokploy and NetBird
were not deployed.

Current retention and storage policy:

- Prometheus retention: 3 days
- Prometheus storage: 25 GiB `manual-local`
- Loki retention: 7 days
- Loki storage: local persistent volume
- Grafana: existing local PVC

Important monitoring settings remain explicit because they are operational
policy rather than redundant configuration:

- Cross-namespace ServiceMonitor, PodMonitor, and PrometheusRule discovery
- k3s-incompatible control-plane scrapers disabled
- Resource requests and limits
- Persistence and retention
- Grafana authentication and ingress
- Alertmanager existing secret
- Traefik timeouts required by uploads and streaming

## Service Endpoints

- Linkding: `https://links.def4alt.com`
- Grafana: `https://grafana.def4alt.com`

Linkding is deployed with local persistent storage and is included in Blackbox
Exporter monitoring.

## Cleanup Completed

Repository cleanup:

- Removed retired Longhorn Helm and recurring-job manifests.
- Removed the unused Pi-hole Longhorn PVC manifest.
- Removed stale Longhorn documentation.
- Removed Longhorn labels and storage assumptions from shared Glance and
  Paperless PVC bases.
- Simplified home and Hetzner Kustomize patches accordingly.
- Removed obsolete Flux v1 annotations from Authentik.
- Removed Helm values that only repeated the pinned chart defaults.
- Removed inactive pre-migration Immich and JuiceFS database definitions.
- Normalized manifest filenames without changing live Kubernetes object names.

Runtime cleanup on `perun`:

- Removed one unowned, failed, 44-day-old JuiceFS recovery-check pod.
- Removed seven Released Longhorn PV objects.
- Cleared obsolete Longhorn finalizers after confirming no Longhorn PV was Bound.
- Removed `/var/lib/longhorn`, reclaiming approximately 55 GiB.
- Disk utilization dropped from approximately 83% to 77%.
- No non-running or dangling pods remained after cleanup.

Do not rename existing Kubernetes object names such as `*-db-local`,
`perun-*-local`, PVC names, or PV names merely to match the new filenames. Those
names participate in immutable storage bindings and changing them would create
or replace resources.

## Naming Convention

Files now use directory-local Kubernetes naming:

- App-local resources use names such as `deployment.yaml`, `service.yaml`,
  `ingress.yaml`, `pvc.yaml`, and `postgres-cluster.yaml`.
- Namespace files under `apps/namespaces` use the namespace name directly, such
  as `authentik.yaml` and `home-assistant.yaml`.
- Files under `apps/local-storage` use the workload or purpose directly, such as
  `immich-db.yaml` and `monitoring-prometheus.yaml`.
- Redundant prefixes and suffixes such as `namespace-`, `pv-`, `-local.yaml`,
  `grafana-dashboard-`, and `zorya-migrated-` were removed.

Component qualifiers are retained when a directory contains multiple resources
of the same kind, for example Loki and Alloy resources under `apps/monitoring`.

## Version Policy

Active Helm releases are pinned to the versions that were already deployed:

- Authentik: chart `2026.5.5`
- cert-manager: chart `v1.21.0`
- CloudNativePG: chart `0.29.0`
- CNPG Barman plugin: chart `0.3.1`
- Home Assistant: chart `0.3.70`
- MetalLB: chart `0.16.1`
- Traefik: chart `41.0.2`
- kube-prometheus-stack: chart `87.17.0`
- Prometheus Blackbox Exporter: chart `11.15.1`
- Minecraft: chart `5.1.2`

Previously mutable application image references were pinned to the exact running
digests. Explicit `imagePullPolicy: Always` values were removed where immutable
digests make them unnecessary.

Minimal configuration does not mean accepting mutable `latest` charts or images.
Version pins, storage bindings, resource limits, and security settings should
remain explicit. Update chart versions and image digests deliberately as grouped,
tested maintenance changes.

## Alertmanager Fix

Alertmanager Telegram delivery was failing because its Go template used an
unsupported `else if` branch inside a `with` block. The encrypted SOPS secret was
corrected to render optional labels independently.

The decrypted configuration passed:

```sh
amtool check-config alertmanager.yaml
```

The deployed secret was also piped directly into `amtool` inside the running
Alertmanager container and passed validation. After reconciliation there were no
Telegram delivery errors in the five-minute log window. The only firing alerts
were the expected `Watchdog` and `InfoInhibitor` meta-alerts.

Never write the decrypted Alertmanager secret or any other secret into the
repository. Use SOPS and remove temporary decrypted files immediately.

## Validation Results

At the end of the work:

- Flux GitRepository was Ready at revision `6c13fd0`.
- Every Flux Kustomization was Ready.
- Every HelmRelease was Ready.
- Every pod had all containers Ready and was Running.
- Every persistent volume was Bound.
- No Longhorn PVs remained.
- Prometheus had no down scrape targets.
- All 17 Blackbox Exporter probes succeeded.
- Loki returned `ready` from its readiness endpoint.
- Alertmanager had no recent notification delivery errors.
- All active home and Hetzner Kustomize paths built successfully.
- `nix flake check path:./nixos --no-build` passed.
- Evaluating NixOS configuration names returned only `["perun"]`.

## Relevant Commits

- `2663c4a chore: simplify homelab configuration`
- `6ff7bee fix(monitoring): repair telegram alert template`
- `6c13fd0 refactor: normalize manifests and nixos hosts`

## ExecPlan

The implementation record is:

```text
.agent/plans/2026-07-17-minimal-homelab-configuration.md
```

An earlier service and observability deployment record is:

```text
.agent/plans/2026-07-17-homelab-services-observability-upgrades.md
```

Historical ExecPlans may mention removed components and old filenames. They are
operational history and should not be rewritten to match the current tree.

## Operational Workflow

Prefer GitOps for changes:

1. Edit manifests in this repository.
2. Build every affected Kustomize path locally.
3. Run `git diff --check`.
4. Validate `nixos` when its files change.
5. Commit using Conventional Commits and push `main`.
6. Reconcile Flux and wait for all dependencies and rollouts.
7. Verify pods, PVs, Prometheus targets, Blackbox probes, Loki, and alerts.

Useful local checks:

```sh
kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/monitoring >/dev/null
kubectl kustomize --load-restrictor=LoadRestrictionsNone apps/local-storage >/dev/null
XDG_CACHE_HOME=/private/tmp/nix-cache nix flake check path:./nixos --no-build
XDG_CACHE_HOME=/private/tmp/nix-cache nix eval \
  path:./nixos#nixosConfigurations --apply builtins.attrNames --json
git diff --check
```

Cluster commands may require SSH and sudo. Obtain credentials from the operator;
do not place passwords, private SOPS Age keys, Cloudflare tokens, Telegram tokens,
or other secrets in this file or Git history.

## Current Follow-Up State

There are no known failed workloads, storage leaks, monitoring target failures,
or pending cleanup tasks from this work. Future maintenance should focus on
deliberate chart and image updates, backup verification, and normal capacity
monitoring rather than adding overlapping observability products.
