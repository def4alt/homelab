# Add homelab services, centralized logs, and platform upgrades

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

This document is maintained in accordance with `.agent/PLANS.md` from the repository root.

## Purpose / Big Picture

After this change, the home cluster provides a bookmark manager at `https://links.def4alt.com`, a Beszel systems dashboard, Uptime Kuma availability monitoring, the existing Grafana instance with Kubernetes logs from Loki, and a Dokploy control plane. All application state survives pod or host restarts. The existing workloads and Helm-managed infrastructure run refreshed images, perun runs the newest tested NixOS generation from the configured `nixos-26.05` channel, and all public UIs are reachable through the existing Cloudflare, Traefik, TLS, and Authentik path.

NetBird is explicitly outside this plan because the user removed it from scope.

## Progress

- [x] (2026-07-17) Read repository instructions, existing plans, application patterns, monitoring manifests, DNS declarations, and NixOS configuration.
- [x] (2026-07-17) Inventory perun over its Tailscale address and confirm capacity, ports, NixOS generation, Flux health, storage, Grafana health, and Docker state.
- [x] (2026-07-17) Confirm Linkding must use `links.def4alt.com` and remove NetBird from scope.
- [x] (2026-07-17) Add retained local storage, namespaces, Kubernetes workloads, ingress, and Flux wiring for Linkding, Beszel, and Uptime Kuma.
- [x] (2026-07-17) Enable the existing Grafana ingress and add monolithic Loki plus Grafana Alloy log collection and a provisioned Grafana data source.
- [x] (2026-07-17) Add a declarative, port-isolated Dokploy Docker/Swarm host service without taking ports 80 or 443 from k3s Traefik.
- [x] (2026-07-17) Audit all live image references; update stale JuiceFS and Authentik pins and correct mutable image pull policies while preserving already-current Helm-managed components.
- [ ] Update the NixOS flake lock, evaluate the configuration, commit and push the GitOps changes, and reconcile application changes in stages (completed: lock updated to nixpkgs `4382ed2`, all local rendering and Nix evaluation pass; remaining: commit, push, and reconcile).
- [ ] Back up stateful data, build and activate the new perun NixOS generation, reboot if required, and verify node, Flux, applications, logs, and public endpoints.
- [ ] Record exact versions, validation evidence, rollback artifacts, and outcomes in this plan.

## Surprises & Discoveries

- Observation: Grafana is already deployed and healthy as part of `kube-prometheus-stack`, but both Grafana and Prometheus ingress are disabled in `apps/monitoring/helmrelease.yaml` even though their public DNS names are declared.
  Evidence: `monitoring-grafana` reported `3/3 Running`; the Helm values set `grafana.ingress.enabled: false`.

- Observation: perun has no active Docker daemon, while Dokploy officially requires Docker Swarm and normally claims ports 80, 443, and 3000.
  Evidence: `systemctl is-active docker` returned `inactive`; k3s Traefik already serves the cluster through ports 80 and 443.

- Observation: perun has enough immediate capacity for lightweight additions but little completely free memory, so resource limits and single-replica deployments are required.
  Evidence: the host has 166 GiB disk free and about 6.2 GiB available memory, with 9.4 GiB currently used.

- Observation: the LAN SSH address was unreachable from the operator machine, but the documented Tailscale address works with key authentication.
  Evidence: `192.168.88.189:22` timed out; `perun@100.119.240.70` returned the host inventory.

- Observation: Most Helm-managed images were already current because their Helm releases track current chart versions; stale behavior was concentrated in hand-written Deployments using mutable tags with `IfNotPresent` and the vendored JuiceFS manifest.
  Evidence: the live inventory included Grafana 13.1.0, Traefik 3.7.6, cert-manager 1.21.0, Prometheus 3.13.1, Authentik 2026.5.5, and Home Assistant 2026.7.2, while JuiceFS remained at 0.31.3.

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

- Decision: Keep Dokploy on perun's host Docker/Swarm runtime but bind its admin and managed ingress to dedicated non-conflicting ports. Route the Dokploy admin hostname through k3s Traefik to the host endpoint.
  Rationale: Dokploy requires Docker Swarm and its own Docker socket; installing its default layout would collide with k3s Traefik on ports 80 and 443. Isolation preserves both orchestrators and makes rollback possible by stopping Docker.
  Date/Author: 2026-07-17 / Codex

- Decision: Use `links.def4alt.com`, `beszel.def4alt.com`, `uptime.def4alt.com`, and `dokploy.def4alt.com` as public UI hostnames. Loki remains cluster-internal and is queried through Grafana.
  Rationale: These names are concise and consistent with existing service hostnames, while exposing Loki directly provides no user benefit.
  Date/Author: 2026-07-17 / Codex

- Decision: Upgrade workloads before NixOS, and upgrade the host only after persistent state and service health are proven.
  Rationale: Separating application and operating-system changes narrows rollback scope and ensures the node reboot is not mixed with untested data migrations.
  Date/Author: 2026-07-17 / Codex

## Outcomes & Retrospective

Repository implementation and local validation are complete. No workload or host changes have been applied yet.

## Context and Orientation

Flux is the in-cluster controller that continuously applies Git manifests from this repository. Application manifests live under `apps/<name>/`; cluster-level Flux `Kustomization` objects live under `clusters/home/overlays/apps/` or `clusters/home/overlays/infra/`; and `clusters/home/overlays/kustomization.yaml` activates them. Namespaces are declared under `apps/namespaces`, and retained local persistent volumes are declared under `apps/local-storage`. Public hostnames are managed from `cloudflare/locals.tf` and route through the existing Cloudflare tunnel to Traefik.

The monitoring stack lives in the `infra` namespace under `apps/monitoring`. It is a `kube-prometheus-stack` Helm release with persistent Prometheus and Grafana volumes. Loki is a log database, not a metrics database. Grafana Alloy is the node-level collector that reads Kubernetes container log files and sends them to Loki.

Perun is a single-node NixOS k3s server. Its declarative host configuration is `nixos/flake.nix` plus `nixos/configuration.nix`, and its exact package snapshot is recorded in `nixos/flake.lock`. Docker is currently disabled. Dokploy is not a Kubernetes application: it manages Docker Swarm services and generates configuration for its own Traefik. Therefore the Dokploy runtime belongs in NixOS configuration and must use ports that do not conflict with the k3s Traefik service.

## Plan of Work

First, add namespaces and retained local volumes for Linkding, Beszel, Uptime Kuma, and Loki. Each application directory will contain a minimal Deployment, Service, Ingress, persistent-volume claim, and Kustomization. Linkding will use its supported SQLite storage path. Beszel will persist its hub database; its perun agent will be added only through a least-privilege mechanism that can observe the host without mounting the k3s container runtime socket read-write. Uptime Kuma will persist `/app/data`. Each UI will use Traefik, cert-manager, and the existing Authentik forward-auth middleware.

Second, extend `apps/monitoring` with the supported Loki Helm chart in monolithic mode, filesystem persistence, short homelab retention, and conservative resources. Add Grafana Alloy to collect `/var/log/pods` and provision Loki as a Grafana data source. Enable Grafana's existing ingress at `grafana.def4alt.com`; keep Prometheus protected and unchanged unless validation shows its existing DNS entry should also be enabled.

Third, add NixOS options that enable Docker only on perun and define a systemd-managed Dokploy bootstrap/update service. The service must use pinned upstream images, persistent data below `/var/lib/dokploy`, a dedicated Swarm address pool that does not overlap the k3s pod or service networks, an admin port reachable only through the cluster ingress path, and alternate Docker Traefik ports. Kubernetes will receive a Service without a selector plus explicit Endpoints or EndpointSlice pointing at perun's LAN address, and an authenticated ingress for the Dokploy admin UI. The design must not publish Docker's API or socket over the network.

Fourth, inventory the actual running images and Helm releases, compare them with current stable upstream releases, and update direct version pins and chart versions. Mutable tags such as `latest` or `release` must be restarted deliberately so new digests are pulled. Stateful upgrades are applied one workload at a time, with database and retained-volume backups before any documented migration boundary.

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

Dokploy's authenticated admin UI must load at `https://dokploy.def4alt.com`. `ss -lntup` on perun must show that k3s continues to own the existing ingress path and Dokploy uses only its assigned alternate ports. Docker must not listen on a TCP API port. Creating a minimal test service in Dokploy and reaching it through the documented alternate ingress path proves the control plane is operational.

After the NixOS activation and reboot, `nixos-version` must report the updated revision, `k3s kubectl get nodes` must show perun Ready, every Flux Kustomization must be Ready, Docker and Dokploy must be active, and all old and new public endpoints must return their expected HTTP or authentication responses.

## Idempotence and Recovery

Flux resources, systemd units, Docker networks, and Swarm initialization must be written as create-if-absent operations so reconciliation and host rebuilds can be repeated safely. Persistent volumes use `Retain`, so removing a Deployment does not delete application data.

If a Kubernetes application fails, revert its Git commit or suspend only its Flux Kustomization while preserving the volume. If Loki overloads the node, suspend Loki and Alloy without touching Grafana or Prometheus. If Dokploy interferes with networking, stop and disable its systemd unit and Docker; k3s must remain independent. If the NixOS generation fails, select the previous boot generation or run `sudo nixos-rebuild switch --rollback`. Do not garbage-collect old NixOS generations or delete backups until the complete acceptance check passes.

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

Linkding uses `ghcr.io/sissbruecker/linkding` and listens on port 9090 with state in `/etc/linkding/data`. Beszel uses the official `henrygd/beszel` hub and `henrygd/beszel-agent` images and listens on port 8090. Uptime Kuma uses `louislam/uptime-kuma:2`, listens on port 3001, and persists `/app/data`.

Loki uses the Grafana Community Loki Helm chart in monolithic mode. Grafana Alloy uses the official Grafana Helm chart or manifests supported by Grafana and sends logs to Loki's in-cluster HTTP endpoint. Grafana receives a provisioned Loki data source through the existing Helm release.

Dokploy uses its official Docker images and Docker Swarm. Its host service must never take perun ports 80 or 443, must not expose `/var/run/docker.sock` beyond the Dokploy and Docker Traefik containers that require it, and must use a non-overlapping Swarm address pool.

Change note: Created the plan after repository and live-cluster discovery; incorporated the requested Linkding hostname, the existing Grafana deployment, the later request to upgrade all images and NixOS, and the explicit removal of NetBird from scope.

Change note: Recorded completion of the declarative manifests, image audit, NixOS lock update, and successful local render/evaluation checks before the first deployment commit.
