# Add Grafana and Prometheus via kube-prometheus-stack

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with that file.

## Purpose / Big Picture

After this change, the homelab has a working Prometheus time-series database and Grafana UI reachable via HTTPS, protected by the existing Traefik + Authentik forward-auth middleware. A user can navigate to `https://prometheus.def4alt.com` to query metrics and `https://grafana.def4alt.com` to build dashboards, and Glance can show the service health using the monitor widget. The observable outcome is that both endpoints return their web UIs and the Prometheus target list contains core Kubernetes exporters.

## Progress

- [x] (2025-02-14 21:00Z) Define a new monitoring stack under `apps/monitoring` using the kube-prometheus-stack Helm chart and wire it into Flux.
- [x] (2025-02-14 21:00Z) Configure ingress, persistence, and k3s-safe defaults for Prometheus and Grafana.
- [x] (2025-02-14 21:20Z) Add Grafana dashboard provisioning for CNPG backup metrics via ConfigMap and sidecar settings.
- [x] (2025-02-14 22:30Z) Add SOPS-managed Grafana admin secret and wire Grafana to use it.
- [ ] (pending) Validate resources with kustomize and document the manual checks to confirm UIs are reachable.

## Surprises & Discoveries

None yet.

## Decision Log

- Decision: Use the `prometheus-community/kube-prometheus-stack` Helm chart to deploy Prometheus and Grafana together in the `infra` namespace.
  Rationale: It provides a cohesive, minimal setup with Prometheus Operator integration and a Grafana instance out-of-the-box, reducing the number of moving pieces.
  Date/Author: 2025-02-14 / Codex

- Decision: Disable kube-etcd, kube-scheduler, kube-controller-manager, and kube-proxy scrapes by default for k3s compatibility.
  Rationale: k3s does not expose these components via the standard service endpoints, which otherwise causes noisy scrape errors.
  Date/Author: 2025-02-14 / Codex

## Outcomes & Retrospective

Pending.

## Context and Orientation

Flux applies Helm charts through `HelmRepository` and `HelmRelease` manifests stored under `apps/<name>/`. Each app has a `kustomization.yaml` that lists resources, and the cluster-level `clusters/home/overlays/kustomization.yaml` references an `infra/<name>.yaml` Flux `Kustomization` to apply the app directory. Ingresses in this repo use Traefik annotations and Authentik forward-auth middleware, plus cert-manager for TLS (see `apps/immich/ingress.yaml`).

For this change, the new files will live under `apps/monitoring/` and a new `clusters/home/overlays/infra/monitoring.yaml` will be added to the overlay list.

## Plan of Work

Create `apps/monitoring/helmrepository.yaml` pointing at `https://prometheus-community.github.io/helm-charts`. Create `apps/monitoring/helmrelease.yaml` for the `kube-prometheus-stack` chart in the `infra` namespace, enabling ingress for Grafana and Prometheus with the same Traefik annotations used elsewhere and TLS secrets `grafana-tls` and `prometheus-tls`. Configure Prometheus persistence to use Longhorn with a 25Gi PVC and set a modest retention window. Enable Grafana persistence with a small PVC (5Gi) and keep default admin credential handling to avoid adding new secrets.

Add `apps/monitoring/kustomization.yaml` listing the Helm resources. Then add `clusters/home/overlays/infra/monitoring.yaml` as a Flux Kustomization pointing to `./apps/monitoring`, and include it in `clusters/home/overlays/kustomization.yaml` so Flux applies it.

## Concrete Steps

All commands run from `/Users/def4alt/source/homelab`.

1) Create the new monitoring app manifests:
   - `apps/monitoring/helmrepository.yaml`
   - `apps/monitoring/helmrelease.yaml`
   - `apps/monitoring/kustomization.yaml`

2) Add Flux wiring:
   - `clusters/home/overlays/infra/monitoring.yaml`
   - Add `infra/monitoring.yaml` to `clusters/home/overlays/kustomization.yaml`.

3) Sanity-check manifests locally:
   - Run `kustomize build apps/monitoring` and expect YAML output with a HelmRelease and HelmRepository.
   - Run `kustomize build clusters/home/overlays` and expect no kustomize errors.

## Validation and Acceptance

After Flux applies the changes, open:

  - `https://grafana.def4alt.com` and expect the Grafana login page.
  - `https://prometheus.def4alt.com` and expect the Prometheus UI.

Within Prometheus, visit `Status -> Targets` and confirm that `kube-state-metrics` and `node-exporter` show as `UP`. If Authentik middleware is enabled, the browser should be challenged for authentication before the UI loads.

## Idempotence and Recovery

These manifests are safe to re-apply; Flux will reconcile them to the same state. If ingress hostnames or storage sizes need to change, update the HelmRelease values and let Flux roll the new configuration. If Prometheus storage becomes too small, increase the PVC request size in the HelmRelease and allow Kubernetes to expand the volume.

## Artifacts and Notes

None yet.

## Interfaces and Dependencies

The Helm chart dependency is `kube-prometheus-stack` from the `prometheus-community` Helm repository. The chart must be referenced by `apps/monitoring/helmrelease.yaml` with `metadata.name: monitoring` and `namespace: infra`. Ingress must use Traefik annotations and Authentik middleware, consistent with other app ingresses in this repo.

Change note: Initial plan created to add Grafana and Prometheus via kube-prometheus-stack with Traefik ingress and Longhorn persistence.
Change note: Marked planning and configuration milestones complete after adding monitoring manifests and Flux wiring.
Change note: Added Grafana dashboard provisioning for CNPG backup metrics using a labeled ConfigMap.
Change note: Added SOPS-managed Grafana admin secret and configured Grafana to use it.
