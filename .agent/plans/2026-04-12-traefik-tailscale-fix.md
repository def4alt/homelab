# Fix Traefik rollout deadlock and Tailscale manifest parse error

This ExecPlan is a living document. Keep `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` updated as work proceeds.

## Purpose / Big Picture

After this change, Flux can reconcile the core edge services again on the single-node homelab:

- Traefik upgrades without stalling on a second pod that cannot schedule on the only node.
- Tailscale renders cleanly so Flux can apply the DaemonSet instead of failing the Kustomize build.
- The dependent app Kustomizations that wait on Traefik and Authentik can resume reconciliation once the edge path is healthy again.

This keeps the cluster aligned with the single-node topology and removes the current GitOps deadlock.

## Progress

- [x] (2026-04-12) Inspect live Traefik and Tailscale state, Flux status, and chart values.
- [x] Update Tailscale probe commands so the DaemonSet YAML parses cleanly.
- [x] Adjust Traefik rollout strategy for a single-node cluster so upgrades do not deadlock on pod anti-affinity.
- [x] Validate manifests with kustomize rendering.
- [ ] Observe Flux reconcile and confirm Traefik/Tailscale return to Ready.

## Surprises & Discoveries

- The Traefik chart is already running with a single replica, but the rollout strategy still tries to create a replacement pod before deleting the old one. On one node, that collides with the existing anti-affinity and stalls the Helm upgrade.
- The Tailscale manifest failure is not a semantic problem with the probe logic; it is a YAML parsing problem caused by an unquoted shell command containing `*`.
- Flux dependency chaining means Traefik being stalled prevents a large portion of the app layer from reconciling, even when many live pods are still running fine.

## Decision Log

- Decision: Use a conservative single-node rollout for Traefik by removing surge-based replacement during upgrades.
  Rationale: There is only one node, so a surge pod cannot schedule alongside the existing Traefik pod when anti-affinity is in play.
  Date/Author: 2026-04-12 / Codex

- Decision: Quote the Tailscale probe command strings instead of changing the probe mechanism.
  Rationale: The existing probe logic is already correct; only YAML scalar parsing needs to be fixed.
  Date/Author: 2026-04-12 / Codex

## Outcomes & Retrospective

In progress. Manifest fixes are in place and validated; waiting on Flux reconcile after the commit is pushed.

## Context and Orientation

The affected manifests live under `apps/traefik/helmrelease.yaml` and `apps/tailscale/daemonset.yaml`. Flux applies them through `clusters/home/overlays/infra/traefik.yaml` and `clusters/home/overlays/infra/tailscale.yaml`.

The live cluster is single-node (`perun`). Traefik currently fails its Helm upgrade because a new pod cannot schedule while the old pod still exists. Tailscale currently fails `kustomize build` because the shell command in the probe list is not quoted as a YAML scalar.

## Plan of Work

1. Update the Tailscale startup/readiness/liveness probe command strings so the YAML parses cleanly.
2. Update Traefik’s HelmRelease rollout strategy so upgrades do not require a second schedulable pod on the only node.
3. Validate both manifests with `kubectl kustomize`.
4. Let Flux reconcile and confirm the Traefik and Tailscale Kustomizations become Ready.

## Concrete Steps

1. Edit `apps/tailscale/daemonset.yaml` to quote the shell command strings used by the probes.
2. Edit `apps/traefik/helmrelease.yaml` to use a single-node-safe rollout strategy.
3. Render the affected kustomizations and confirm they build without errors.
4. Watch Flux status and the live Traefik/Tailscale pods after the commit lands.

## Validation and Acceptance

- `kubectl kustomize apps/tailscale` succeeds.
- `kubectl kustomize apps/traefik` succeeds.
- Flux reports `traefik` and `tailscale` as Ready after reconcile.
- Traefik no longer leaves a Pending replacement pod during upgrades.
- Tailscale starts without probe-related YAML parse failures.

## Idempotence and Recovery

These are declarative manifest changes and safe to reapply. If Traefik still stalls after the rollout change, revert only the Traefik strategy block and inspect the chart behavior further. If Tailscale still fails to parse, simplify the probe command into a block scalar or a shell script wrapper.

## Artifacts and Notes

- `apps/traefik/helmrelease.yaml`
- `apps/tailscale/daemonset.yaml`

## Interfaces and Dependencies

- Flux `Kustomization` objects in `flux-system`
- Traefik Helm chart `traefik@39.0.7`
- Tailscale container image `tailscale/tailscale:latest`

Change note: Initial plan created to restore Traefik and Tailscale reconciliation on the single-node cluster.
