# Add homelab services, centralized logs, and platform upgrades

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document is maintained in accordance with `.agent/PLANS.md` from the repository root.

## Purpose / Big Picture

After this change, the home cluster provides a bookmark manager at `https://links.def4alt.com`, a Beszel systems dashboard, Uptime Kuma availability monitoring, and the existing Grafana instance with Kubernetes logs from Loki. All application state survives pod or host restarts. The existing workloads and Helm-managed infrastructure run refreshed images, perun runs the newest tested NixOS generation from the configured `nixos-26.05` channel, and all public UIs are reachable through the existing Cloudflare, Traefik, TLS, and Authentik path.

NetBird and Dokploy are explicitly outside this plan because the user removed them from scope.

## Progress

- [x] (2026-07-17) Read repository instructions, existing plans, application patterns, monitoring manifests, DNS declarations, and NixOS configuration.
- [x] (2026-07-17) Inventory perun over its Tailscale address and confirm capacity, ports, NixOS generation, Flux health, storage, Grafana health, and Docker state.
- [x] (2026-07-17) Confirm Linkding must use `links.def4alt.com` and remove NetBird from scope.
- [x] (2026-07-17) Add retained local storage, namespaces, Kubernetes workloads, ingress, and Flux wiring for Linkding, Beszel, and Uptime Kuma.
- [x] (2026-07-17) Enable the existing Grafana ingress and add monolithic Loki plus Grafana Alloy log collection and a provisioned Grafana data source.
- [x] (2026-07-17) Remove Dokploy from NixOS, Kubernetes, monitoring, and DNS after the user removed it from scope.
- [x] (2026-07-17) Audit all live image references; update stale JuiceFS and Authentik pins and correct mutable image pull policies while preserving already-current Helm-managed components.
- [x] (2026-07-17) Update the NixOS flake lock, evaluate the configuration, commit and push the GitOps changes, and reconcile application changes in stages.
- [x] (2026-07-17) Back up stateful data, build and activate NixOS `26.05.20260716.4382ed2` with kernel `6.18.38`, and reboot perun.
- [x] (2026-07-17) Verify node, Flux, applications, logs, certificates, and public endpoints; remove old NixOS generations and garbage collect the store.
- [x] (2026-07-17) Record exact versions, validation evidence, rollback artifacts, and outcomes in this plan.
- [x] (2026-07-17) Connect Prometheus, Alertmanager, Grafana, Loki, Alloy, blackbox exporter, Beszel, and Uptime Kuma into one validated observability workflow.
- [ ] (2026-07-17) Remove Beszel and Uptime Kuma after selecting the lean Prometheus, Grafana, Alertmanager, Loki, Alloy, and blackbox architecture.

## Surprises & Discoveries

- Observation: Grafana is already deployed and healthy as part of `kube-prometheus-stack`, but both Grafana and Prometheus ingress are disabled in `apps/monitoring/helmrelease.yaml` even though their public DNS names are declared.
  Evidence: `monitoring-grafana` reported `3/3 Running`; the Helm values set `grafana.ingress.enabled: false`.

- Observation: A direct `switch-to-configuration` activation does not advance the NixOS system profile; `nixos-rebuild switch --flake` was required before rebooting.
  Evidence: the first reboot selected generation 21, while the corrected switch advanced `/nix/var/nix/profiles/system` to generation 22 and booted `26.05.20260716.4382ed2` with kernel `6.18.38`.

- Observation: perun has enough immediate capacity for lightweight additions but little completely free memory, so resource limits and single-replica deployments are required.
  Evidence: the host has 166 GiB disk free and about 6.2 GiB available memory, with 9.4 GiB currently used.

- Observation: the LAN SSH address was unreachable from the operator machine, but the documented Tailscale address works with key authentication.
  Evidence: `192.168.88.189:22` timed out; `perun@100.119.240.70` returned the host inventory.

- Observation: Most Helm-managed images were already current because their Helm releases track current chart versions; stale behavior was concentrated in hand-written Deployments using mutable tags with `IfNotPresent` and the vendored JuiceFS manifest.
  Evidence: the live inventory included Grafana 13.1.0, Traefik 3.7.6, cert-manager 1.21.0, Prometheus 3.13.1, Authentik 2026.5.5, and Home Assistant 2026.7.2, while JuiceFS remained at 0.31.3.

- Observation: Loki's first start could not create its rules directory because the retained hostPath was root-owned; Kubernetes did not apply the pod `fsGroup` to the hostPath-backed volume.
  Evidence: Loki exited with `mkdir /var/lib/loki/rules: permission denied`; the fix is a root init container that changes ownership to Loki UID/GID 10001 before the main container starts.

- Observation: Creating four certificates simultaneously triggered Cloudflare DNS API throttling rather than a cert-manager resource error.
  Evidence: challenge reasons returned Cloudflare errors `971: Please wait and consider throttling your request speed` and `10502: Too many authentication failures. Please try again later`.

- Observation: perun's DHCP-provided resolver at `192.168.88.1` stopped answering after reboot, and CoreDNS retained that resolver until its pod restarted.
  Evidence: host IP connectivity remained healthy while CoreDNS logged upstream UDP timeouts; temporarily using `1.1.1.1` and restarting CoreDNS restored Flux, ACME, and Helm repository resolution.

- Observation: The encrypted cert-manager Cloudflare token could no longer list zones, while the credential used by OpenTofu still had working zone access.
  Evidence: replacing only the SOPS-encrypted `cloudflare-dns` value and recreating the stale challenges resulted in all four new certificates becoming `Ready=True`.

- Observation: Pulling Immich `v3.0.3` exposed that restored application tables were owned by `postgres`, preventing the new migration from altering `asset`.
  Evidence: an immediate 21 MiB `pg_dump` was taken, ownership of public non-extension objects was transferred to `immich`, and the server then completed migrations and remained `Running` with zero restarts.

## Decision Log

- Decision: Deploy Linkding, Beszel hub, Uptime Kuma, Loki, and the log collector through k3s and Flux, each with retained host-backed storage where state is required.
  Rationale: This matches the repository's GitOps model and avoids introducing a second unmanaged application runtime for services that work well in Kubernetes.
  Date/Author: 2026-07-17 / Codex

- Decision: Keep Grafana in the existing `apps/monitoring` Helm release and add an ingress and Loki data source instead of deploying another Grafana.
  Rationale: A duplicate Grafana would waste resources and split dashboards, credentials, and persistence.
  Date/Author: 2026-07-17 / Codex

- Decision: Run Loki in monolithic mode with filesystem storage and one replica, and use Grafana Alloy as a DaemonSet-style Kubernetes log collector.
  Rationale: Grafana recommends monolithic Loki for small meta-monitoring installations; a single-node homelab does not benefit from the operational cost of microservices mode.
  Date/Author: 2026-07-17 / Codex

- Decision: Keep Prometheus and Alertmanager as the single metrics and alerting control plane, and treat Beszel and Uptime Kuma as focused user interfaces rather than parallel telemetry pipelines.
  Rationale: Duplicating collection and alert routing would create inconsistent health states. Prometheus can centrally observe both specialist applications through blackbox probes while Grafana correlates cluster metrics and Loki logs.
  Date/Author: 2026-07-17 / Codex

- Decision: Remove Beszel and Uptime Kuma and keep kube-prometheus-stack, Grafana, Prometheus, Alertmanager, monolithic Loki, Alloy, and blackbox exporter as the complete observability stack.
  Rationale: The specialist UIs duplicate host and availability functionality already covered by node exporter, Grafana, Prometheus, Alertmanager, and blackbox exporter. Removing them reduces stateful services, public routes, certificates, and upgrade surface without losing telemetry.
  Date/Author: 2026-07-17 / User and Codex

- Decision: Use `links.def4alt.com`, `beszel.def4alt.com`, and `uptime.def4alt.com` as public UI hostnames. Loki remains cluster-internal and is queried through Grafana.
  Rationale: These names are concise and consistent with existing service hostnames, while exposing Loki directly provides no user benefit.
  Date/Author: 2026-07-17 / Codex

- Decision: Upgrade workloads before NixOS, and upgrade the host only after persistent state and service health are proven.
  Rationale: Separating application and operating-system changes narrows rollback scope and ensures the node reboot is not mixed with untested data migrations.
  Date/Author: 2026-07-17 / Codex

- Decision: Declare Cloudflare's resolvers on perun instead of returning to the unresponsive DHCP-provided router resolver.
  Rationale: Flux, CoreDNS, ACME, image pulls, and Nix downloads all require a working recursive resolver across reboots; leaving the recovery edit only in `/etc/resolv.conf` would create configuration drift.
  Date/Author: 2026-07-17 / Codex

## Outcomes & Retrospective

Linkding `1.45.0`, Beszel Hub `0.18.7`, and Uptime Kuma `2.4.0` are running with retained local storage and authenticated public routes. Grafana is public through the same Authentik path, Loki `3.7.2` reports ready and returns Kubernetes labels, and Alloy `1.16.1` is forwarding logs without recent errors. All Flux Kustomizations and all certificates are ready at Git revision `8a5383c`.

Perun now runs NixOS `26.05.20260716.4382ed2`, Linux `6.18.38`, k3s `v1.35.6+k3s1`, and containerd `2.2.5-k3s2`. Generation cleanup retained only generation 23 and removed 15,965 unreferenced store paths, freeing 11.5 GiB. Dokploy's Kubernetes, NixOS, Cloudflare, Docker, and host-state artifacts were removed.

Backups retained on perun include the pre-upgrade k3s etcd snapshot, `/var/lib/k8s-backups/20260717T160437Z/new-services.tgz`, and `/var/lib/k8s-backups/20260717T160437Z/immich-pre-v3-owner-fix.sql.gz`. Beszel host-agent enrollment remains a first-login action because the hub generates its agent key only after an administrator initializes the UI.

The observability stack is now connected around one control plane. Prometheus scrapes Loki and Alloy in addition to the existing Kubernetes, node, database, and blackbox targets; Alertmanager sends the resulting warning and critical alerts to Telegram; Alloy enriches logs with `cluster` and `workload` labels before sending them to Loki; and Grafana provisions the `Homelab Observability` dashboard with service availability, node capacity, workload health, log ingestion, restarts, and recent error logs. Internal probes distinguish service failures from ingress, DNS, and TLS failures, while public probes include the requested applications plus Jellyfin and Transmission.

Validation at Git revision `3be9c9b` showed Loki and Alloy scrape targets at `up=1`, 21 of 21 blackbox probes successful, internal and external availability both at 100%, all six custom alert rules loaded, enriched Loki labels available, and the dashboard retrievable through Grafana's API.

## Context and Orientation

Flux is the in-cluster controller that continuously applies Git manifests from this repository. Application manifests live under `apps/<name>/`; cluster-level Flux `Kustomization` objects live under `clusters/home/overlays/apps/` or `clusters/home/overlays/infra/`; and `clusters/home/overlays/kustomization.yaml` activates them. Namespaces are declared under `apps/namespaces`, and retained local persistent volumes are declared under `apps/local-storage`. Public hostnames are managed from `cloudflare/locals.tf` and route through the existing Cloudflare tunnel to Traefik.

The monitoring stack lives in the `infra` namespace under `apps/monitoring`. It is a `kube-prometheus-stack` Helm release with persistent Prometheus and Grafana volumes. Loki is a log database, not a metrics database. Grafana Alloy is the node-level collector that reads Kubernetes container log files and sends them to Loki.

Perun is a single-node NixOS k3s server. Its declarative host configuration is `nixos/flake.nix` plus `nixos/configuration.nix`, and its exact package snapshot is recorded in `nixos/flake.lock`.

## Plan of Work

First, add namespaces and retained local volumes for Linkding, Beszel, Uptime Kuma, and Loki. Each application directory will contain a minimal Deployment, Service, Ingress, persistent-volume claim, and Kustomization. Linkding will use its supported SQLite storage path. Beszel will persist its hub database; its perun agent will be added only through a least-privilege mechanism that can observe the host without mounting the k3s container runtime socket read-write. Uptime Kuma will persist `/app/data`. Each UI will use Traefik, cert-manager, and the existing Authentik forward-auth middleware.

Second, extend `apps/monitoring` with a pinned monolithic Loki deployment, filesystem persistence, short homelab retention, and conservative resources. Add Grafana Alloy to collect `/var/log/pods` and provision Loki as a Grafana data source. Enable Grafana's existing ingress at `grafana.def4alt.com`; keep Prometheus protected and unchanged unless validation shows its existing DNS entry should also be enabled.

Third, inventory the actual running images and Helm releases, compare them with current stable upstream releases, and update direct version pins and chart versions. Mutable tags such as `latest` or `release` must be restarted deliberately so new digests are pulled. Stateful upgrades are applied one workload at a time, with database and retained-volume backups before any documented migration boundary.

Finally, update `nixos/flake.lock`, run local rendering and flake evaluation, commit and push, and let Flux reconcile in stages. After application checks pass, build the NixOS closure on perun, preserve the current system generation as rollback, activate the new generation, reboot if the kernel or foundational services changed, and verify every Flux object and public endpoint again.

## Concrete Steps

Run all repository commands from `/Users/def4alt/source/homelab`.

Render each new application and the complete cluster overlay:

    kubectl kustomize apps/linkding
    kubectl kustomize apps/beszel
    kubectl kustomize apps/uptime-kuma
    kubectl kustomize apps/monitoring
    kubectl kustomize clusters/home/overlays

Validate the NixOS configuration before activation:

    nix flake check ./nixos --no-build
    nix build ./nixos#nixosConfigurations.perun.config.system.build.toplevel

After committing and pushing, reconcile Flux on perun and wait for every changed Kustomization to report `Ready=True`. Use `kubectl rollout status`, application health endpoints, and ingress requests with explicit host headers before testing through Cloudflare.

Before activating NixOS, create an etcd snapshot and filesystem archives for the new persistent application directories. Build and switch with the repository checkout on perun, then reboot only if required by the resulting generation. If SSH does not return on the LAN address, use `100.119.240.70` over Tailscale.

## Validation and Acceptance

`kubectl kustomize clusters/home/overlays` must render without errors. All Flux Kustomizations must report Ready at the pushed Git revision, all pods must become Ready, and no existing application may regress.

`https://links.def4alt.com` must pass through Authentik and render Linkding's initial login/setup UI. Creating a test bookmark, restarting its pod, and retrieving the bookmark proves persistence. Beszel and Uptime Kuma must similarly render setup pages through their chosen hostnames and retain initial configuration across pod restarts.

Grafana must load at `https://grafana.def4alt.com`. Its data sources must include Prometheus and Loki, and an Explore query such as `{namespace="infra"}` must return recent Kubernetes log lines. Loki and Alloy pods must remain within their configured memory limits.

After the NixOS activation and reboot, `nixos-version` must report the updated revision, `k3s kubectl get nodes` must show perun Ready, every Flux Kustomization must be Ready, and all old and new public endpoints must return their expected HTTP or authentication responses.

## Idempotence and Recovery

Flux resources and persistent directories are declarative so reconciliation and host rebuilds can be repeated safely. Persistent volumes use `Retain`, so removing a Deployment does not delete application data.

If a Kubernetes application fails, revert its Git commit or suspend only its Flux Kustomization while preserving the volume. If Loki overloads the node, suspend Loki and Alloy without touching Grafana or Prometheus. If the NixOS generation fails, select a retained boot generation or run `sudo nixos-rebuild switch --rollback` before the requested generation cleanup is performed.

## Artifacts and Notes

Initial live inventory on 2026-07-17:

    perun Ready, k3s v1.35.4+k3s1
    NixOS 26.05.20260531.b51242d
    root filesystem: 931 GiB total, 166 GiB available
    memory: 15 GiB total, about 6.2 GiB available
    Docker: inactive
    Flux: all existing Kustomizations Ready at 67066625
    Grafana: 3/3 Running

## Interfaces and Dependencies

Linkding uses `ghcr.io/sissbruecker/linkding:1.45.0` and listens on port 9090 with state in `/etc/linkding/data`. Beszel uses `henrygd/beszel:0.18.7` and listens on port 8090. Uptime Kuma uses `louislam/uptime-kuma:2.4.0`, listens on port 3001, and persists `/app/data`.

Loki uses `grafana/loki:3.7.2` in monolithic mode. Grafana Alloy uses `grafana/alloy:v1.16.1` and sends logs to Loki's in-cluster HTTP endpoint. Grafana receives a provisioned Loki data source through the existing Helm release.

Change note: Created the plan after repository and live-cluster discovery; incorporated the requested Linkding hostname, the existing Grafana deployment, the later request to upgrade all images and NixOS, and the explicit removal of NetBird from scope.

Change note: Recorded completion of the declarative manifests, image audit, NixOS lock update, and successful local render/evaluation checks before the first deployment commit.

Change note: Removed Dokploy from the implementation and acceptance criteria after the user explicitly removed it from scope.

Change note: Recorded the completed rollout, NixOS and garbage-collection results, certificate rotation, Immich ownership migration, backup paths, and final validation evidence.

Change note: Added and validated the unified observability workflow, including component self-monitoring, internal service probes, external endpoint probes, actionable alert rules, enriched log labels, and a correlated Grafana dashboard.
