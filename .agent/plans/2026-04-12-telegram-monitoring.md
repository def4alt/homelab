# Add Telegram alerting for cluster health and external endpoint checks

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` updated as work proceeds.

## Purpose / Big Picture

After this change, the homelab monitoring stack sends Telegram messages for high-signal alerts. Kubernetes-native issues such as pods not becoming ready, deployments/statefulsets losing availability, PVC problems, and node outages are handled by the existing kube-prometheus-stack alert rules. External endpoint availability is covered by blackbox exporter targets and custom alerts so that public URLs like `auth.def4alt.com`, `pihole.def4alt.com`, and `def4alt.com` trigger Telegram notifications when they stop responding as expected.

The monitoring stack remains decoupled from ingress/auth where possible so that observability still works when the public frontend is degraded.

## Progress

- [x] (2026-04-12) Inspect current monitoring topology, Flux wiring, and kube-prometheus-stack capabilities.
- [x] (2026-04-12) Create a secret-backed Alertmanager configuration that routes warning/critical alerts to Telegram.
- [x] (2026-04-12) Add a Prometheus blackbox exporter release for probing external endpoints.
- [x] (2026-04-12) Add PrometheusRule for probe failures so endpoint outages alert cleanly.
- [x] (2026-04-12) Validate manifests with kustomize-compatible rendering and prepare for Flux reconcile.

## Surprises & Discoveries

- kube-prometheus-stack already ships with a large set of useful cluster health rules by default; this means the Telegram integration can focus on notification delivery and external endpoint checks instead of re-implementing core Kubernetes alerts.
- The chart supports `alertmanager.alertmanagerSpec.useExistingSecret` and `configSecret`, which is a good fit for a SOPS-managed Alertmanager config secret.
- The chart also exposes `ruleSelector`, allowing custom `PrometheusRule` resources to be selected without label gymnastics.

## Decision Log

- Decision: Keep ingress disabled for the monitoring UI and rely on internal access plus Telegram notifications.
  Rationale: This decouples observability from the public ingress/auth path and reduces the chance that monitoring becomes unavailable when the edge is unhealthy.
  Date/Author: 2026-04-12 / Codex

- Decision: Use the existing kube-prometheus-stack alert rules for Kubernetes health and only add custom alerting for blackbox probes.
  Rationale: Reusing the chart’s built-in rules keeps the repo smaller and avoids duplicating mature alert definitions.
  Date/Author: 2026-04-12 / Codex

- Decision: Reuse the existing Telegram bot credentials pattern from the repo and store the Alertmanager config as a SOPS-encrypted secret.
  Rationale: This keeps sensitive values out of plain text while preserving GitOps friendliness.
  Date/Author: 2026-04-12 / Codex

## Outcomes & Retrospective

Pending.

## Context and Orientation

The monitoring stack lives under `apps/monitoring/` and is deployed by Flux through `clusters/home/overlays/infra/monitoring.yaml`. The current monitoring HelmRelease already disables Grafana and Prometheus ingress, which is good for a single-node setup. Flux selectors currently select all ServiceMonitors and PodMonitors; the plan extends that to custom PrometheusRules as well.

The repo already uses SOPS with Age for secrets. The monitoring stack already has a SOPS-managed Grafana admin secret, so adding a SOPS-managed Alertmanager secret follows the same pattern.

## Plan of Work

1. Create a SOPS-managed secret in `apps/monitoring/secrets/` containing the Alertmanager configuration with a Telegram receiver and a route that sends warning/critical alerts to that receiver.
2. Update `apps/monitoring/helmrelease.yaml` so Alertmanager uses that existing secret and Prometheus selects custom `PrometheusRule` resources.
3. Add a `prometheus-blackbox-exporter` HelmRelease under `apps/monitoring/` using the existing Prometheus-community repository.
4. Add blackbox exporter targets for the main public endpoints, and a small `PrometheusRule` that alerts when probe results fail for a few minutes.
5. Update `apps/monitoring/kustomization.yaml` to include the new resources.
6. Validate with kustomize build and then let Flux reconcile.

## Concrete Steps

1. Create or update the monitoring manifests under `/Users/def4alt/source/homelab/apps/monitoring/`.
2. Ensure the new secret is SOPS encrypted and matches the repo’s Age key.
3. Run `kustomize build apps/monitoring` and confirm the manifests render cleanly.
4. Observe the Flux Kustomization and the new Pods/CRs after reconcile.
5. Trigger a safe test alert if possible and verify Telegram delivery.

## Validation and Acceptance

- Alertmanager should start without config errors and expose the Telegram receiver.
- A deliberate blackbox target failure should generate a Telegram message within a few minutes.
- A known Kubernetes health alert should still flow through Alertmanager to Telegram.
- The monitoring stack should remain usable even if Traefik or Authentik is unhealthy.

## Idempotence and Recovery

All changes are GitOps-managed and safe to reapply. If the Telegram configuration causes Alertmanager startup issues, revert the secret and HelmRelease changes together. If the blackbox exporter becomes noisy or too costly, remove the blackbox exporter targets and the exporter release without affecting the main monitoring stack.

## Artifacts and Notes

- `apps/monitoring/secrets/alertmanager.sops.yaml`
- `apps/monitoring/blackbox-exporter-helmrelease.yaml`
- `apps/monitoring/prometheusrules.yaml`

## Interfaces and Dependencies

- `prometheus-community/kube-prometheus-stack`
- `prometheus-community/prometheus-blackbox-exporter`
- Flux Kustomization: `clusters/home/overlays/infra/monitoring.yaml`
- SOPS Age key: repo-managed under the existing homelab setup

Change note: Initial plan created to add Telegram alerting for both Kubernetes health and public endpoint checks.
