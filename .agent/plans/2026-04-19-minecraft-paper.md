# Minecraft Paper Server Homelab Implementation Plan

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

This change adds a Minecraft server to the homelab so players on the LAN can connect to a stable MetalLB address and run a Paper-based server backed by persistent storage. After the change, Flux should reconcile the new Kubernetes resources and the server should come up as a single, stateful game server with its world saved on disk between restarts.

## Progress

- [x] (2026-04-19 00:00Z) Inspected the current Flux/app layout and confirmed there is no existing Minecraft deployment.
- [x] (2026-04-19 00:00Z) Confirmed the desired exposure model: MetalLB LoadBalancer with a fixed LAN IP so Cloudflare can point `minecraft.def4alt.com` at it.
- [x] (2026-04-19 00:00Z) Added a new `apps/minecraft` app folder containing the Helm repository, Helm release, and local kustomization for the `itzg/minecraft` chart configured for Paper.
- [x] (2026-04-19 00:00Z) Added a new `apps/namespaces/namespace-minecraft.yaml` manifest and included it in the namespaces kustomization.
- [x] (2026-04-19 00:00Z) Added the new app Kustomization to `clusters/home/overlays/apps/minecraft.yaml` and registered it in `clusters/home/overlays/kustomization.yaml`.
- [x] (2026-04-19 00:00Z) Updated Cloudflare so `minecraft.def4alt.com` resolves directly to the Minecraft server's MetalLB address instead of going through the HTTP tunnel.
- [x] (2026-04-19 00:00Z) Validated the manifests with `kubectl kustomize` and OpenTofu.
- [x] (2026-04-19 00:00Z) Recorded the final result and follow-up notes in `Outcomes & Retrospective`.

## Surprises & Discoveries

- None yet.

## Decision Log

- Decision: Use the upstream `itzg/minecraft` Helm chart rather than hand-writing Deployment and Service manifests.
  Rationale: The chart already models the Minecraft-specific settings we need, including Paper server type, persistence, and LoadBalancer service exposure.
  Date/Author: 2026-04-19 / Codex

- Decision: Use a fixed MetalLB IP for Minecraft instead of an auto-assigned one.
  Rationale: `minecraft.def4alt.com` needs a stable DNS target, and a fixed address keeps the Cloudflare A record aligned with the service across restarts.
  Date/Author: 2026-04-19 / Codex

- Decision: Use OpenTofu for the Cloudflare project commands instead of Terraform.
  Rationale: The user explicitly asked for OpenTofu, and the repository can keep the same configuration syntax while switching the CLI used for validation and applies.
  Date/Author: 2026-04-19 / Codex

- Decision: Create a dedicated `minecraft` namespace.
  Rationale: This keeps the server isolated from other applications and matches the repository's per-app namespace pattern.
  Date/Author: 2026-04-19 / Codex

## Outcomes & Retrospective

The Minecraft app is now present in `apps/minecraft` and is wired into Flux through `clusters/home/overlays/apps/minecraft.yaml`. The server is configured for Paper, persists its world on Longhorn storage, and is reachable on the LAN through MetalLB at a fixed address that Cloudflare points to from `minecraft.def4alt.com`.

Validation was done locally with `kubectl kustomize` for the Kubernetes manifests and `tofu` for the Cloudflare project. The main follow-up is operational: after Flux applies the manifests, confirm that MetalLB assigns the chosen IP, the Minecraft pod becomes Ready, and the DNS record resolves to that address.

## Context and Orientation

The repository uses Flux GitOps manifests under `apps/` for application resources and `clusters/home/overlays/` for Flux `Kustomization` objects that tell Flux which app directories to reconcile. Existing applications such as `apps/paperless` and `apps/immich` show the local pattern: a per-app `kustomization.yaml`, app manifests in the same folder, and a matching `clusters/home/overlays/apps/<app>.yaml` resource.

For Minecraft, the upstream Helm chart is `itzg/minecraft` from the `https://itzg.github.io/minecraft-server-charts/` repository. The chart exposes Minecraft settings through `minecraftServer.*`, persistence through `persistence.dataDir.*`, and the network service through `minecraftServer.serviceType` and `minecraftServer.loadBalancerIP`.

## Plan of Work

First, add a dedicated namespace manifest in `apps/namespaces/namespace-minecraft.yaml` and register it in `apps/namespaces/kustomization.yaml`. Then create `apps/minecraft/kustomization.yaml`, `apps/minecraft/helmrepository.yaml`, and `apps/minecraft/helmrelease.yaml`. The Helm release should configure Paper, enable the EULA, use persistent storage on Longhorn, and expose the server as a LoadBalancer.

After the app manifests exist, add `clusters/home/overlays/apps/minecraft.yaml` so Flux reconciles the app, and include that overlay in `clusters/home/overlays/kustomization.yaml`. The new Flux Kustomization should depend on `namespaces`, `longhorn`, and `metallb-config` so the namespace, storage backend, and LoadBalancer controller are ready before the app tries to start.

## Concrete Steps

From `/Users/def4alt/source/homelab`, run the following checks after editing files:

    kubectl kustomize apps/namespaces
    kubectl kustomize apps/minecraft
    kubectl kustomize clusters/home/overlays
    tofu -chdir=cloudflare fmt -check
    tofu -chdir=cloudflare validate

If `kubectl kustomize` is not available, use `flux build kustomization` for the relevant Flux resources or validate the YAML with another local parser, but prefer `kubectl kustomize` because this repository is organized around Kustomize. Use OpenTofu rather than Terraform for the Cloudflare project.

## Validation and Acceptance

The change is complete when the new namespace, Helm repository, Helm release, and Flux Kustomization all render successfully, the Cloudflare project validates with OpenTofu, and the app overlay is included in the home cluster overlay tree. The expected user-visible result is a Minecraft server that gets a LAN IP from MetalLB, stores its world on Longhorn-backed persistent storage, and runs Paper instead of vanilla Minecraft while `minecraft.def4alt.com` resolves directly to that server.

## Idempotence and Recovery

The manifests should be safe to apply repeatedly because Flux will reconcile them declaratively. If a rendered manifest fails validation, fix the YAML and rerun the build commands above. If the LoadBalancer is not assigned an address after reconciliation, verify that `metallb` and `metallb-config` are healthy before debugging the Minecraft release itself.

## Artifacts and Notes

No artifacts yet.

## Interfaces and Dependencies

The app will depend on the existing Flux Kustomization graph, the `metallb` and `longhorn` infrastructure, and the `itzg/minecraft` chart values documented in `apps/minecraft/helmrelease.yaml`. No application code changes are required.

Change note: revised after implementation to reflect the added Minecraft app, the direct DNS route for `minecraft.def4alt.com`, the fixed MetalLB IP, and the switch from Terraform command examples to OpenTofu.

Change note: revised after implementation to reflect the added Minecraft app, the direct DNS route for `minecraft.def4alt.com`, and the switch from Terraform command examples to OpenTofu.
