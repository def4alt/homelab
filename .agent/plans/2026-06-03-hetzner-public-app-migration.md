# Migrate selected public apps to the Hetzner cluster

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with PLANS.md.

## Purpose / Big Picture

After this change, the repository will describe a real dual-cluster layout instead of only a dual-cluster skeleton. The Hetzner host `zorya` will serve the public-facing applications that benefit from a public edge location, while the home host `perun` will keep the home-bound and storage-heavy applications. A human should be able to inspect the repo, see exactly which apps reconcile from `clusters/hetzner`, and then verify on the live Hetzner cluster that Flux reports those app Kustomizations as ready.

The first visible outcome is that `blog` serves from Hetzner without changing the home cluster’s private workloads. The next visible outcomes are `authentik`, `glance`, and `paperless` becoming Hetzner-owned in that order. `minecraft` must explicitly stay on `perun`.

## Progress

- [x] (2026-06-03 07:20Z) Confirm the intended public-app split with the user: move `blog`, `authentik`, `glance`, and `paperless` to Hetzner; keep `minecraft` on `perun`.
- [x] (2026-06-03 07:24Z) Record the migration design and implementation sequence in this ExecPlan.
- [x] (2026-06-03 07:45Z) Add Hetzner app overlay objects under `clusters/hetzner/overlays/apps/`, add Hetzner `cnpg` and `traefik-auth` infra overlays, and wire them into `clusters/hetzner/overlays/kustomization.yaml`.
- [x] (2026-06-03 07:46Z) Create Hetzner-specific namespace and storage wrapper paths under `apps/modes/hetzner/` for `authentik`, `blog`, `glance`, and `paperless` prerequisites.
- [x] (2026-06-03 08:00Z) Implement Wave 1 by reconciling `blog` from `clusters/hetzner`; removal from the home-cluster overlay is deferred until traffic cutover is explicit.
- [x] (2026-06-03 08:03Z) Implement Wave 2 by adding Hetzner `cnpg` infrastructure, the `authentik` app, and the Hetzner-only forward-auth middleware path needed by later apps.
- [x] (2026-06-03 08:05Z) Implement Wave 3 by adding `glance` to Hetzner with a Hetzner-specific storage patch that avoids Longhorn.
- [x] (2026-06-03 08:06Z) Implement Wave 4 by adding `paperless` to Hetzner with Hetzner-specific storage patches that avoid Longhorn while keeping its own Postgres and Redis topology.
- [x] (2026-06-03 08:06Z) Validate the staged Hetzner deployments on the live cluster: `blog`, `authentik`, `glance`, `paperless`, `cnpg`, and `traefik-auth` all reconcile successfully.
- [x] (2026-06-03 09:08Z) Execute public traffic cutover by routing `def4alt.com`, `auth.def4alt.com`, `dashboard.def4alt.com`, and `papers.def4alt.com` through the existing Cloudflare tunnel to the Hetzner origin, then remove Hetzner-owned apps from `clusters/home/overlays/kustomization.yaml`.
- [x] (2026-06-03 08:07Z) Update `README.md` so the public-app placement and staged cutover are obvious to a novice operator.

## Surprises & Discoveries

- Observation: The first Hetzner Flux bootstrap accidentally created many home-app namespaces because `clusters/hetzner/overlays/infra/namespaces.yaml` pointed at the shared `apps/namespaces` directory.
  Evidence: the live Hetzner cluster temporarily had namespaces such as `paperless`, `minecraft`, `immich`, and `pi-hole` before the Hetzner-specific namespace overlay replaced them.

- Observation: Reusing `apps/traefik` directly on Hetzner also pulled in home-only middleware definitions, including the Pi-hole redirect middleware.
  Evidence: the initial Hetzner `traefik` Kustomization failed with `Middleware/infra/pihole-root-redirect dry-run failed` until the Hetzner Traefik path was split into its own minimal files.

- Observation: `glance` and `paperless` are not clean “just move the ingress” workloads because they currently rely on storage choices from the home cluster.
  Evidence: `apps/glance/pvc.yaml` sets `storageClassName: longhorn`, and `apps/paperless/pvc.yaml` also sets `storageClassName: longhorn` while `clusters/home/overlays/apps/paperless.yaml` depends on `longhorn` and `cnpg`.

- Observation: `authentik` is the dependency pivot for the public app split.
  Evidence: `apps/glance/ingress.yaml`, `apps/paperless/ingress.yaml`, and `apps/home-assistant/helmrelease.yaml` all reference `infra-authentik-forward-auth@kubernetescrd`.

- Observation: public DNS for the selected hostnames is still Cloudflare-proxied, so merely adding an app to Hetzner does not guarantee external traffic reaches the Hetzner cluster yet.
  Evidence: `dig +short def4alt.com A` and the related hostnames returned Cloudflare proxy IPs (`104.21.27.250`, `172.67.143.208`), not the Hetzner node IP `46.62.137.102`.

- Observation: staging `authentik` on Hetzner while the hostname is still owned by the current public path makes the managed `Certificate/authentik-tls` a poor readiness gate.
  Evidence: the Hetzner `authentik` Kustomization stalled on `Certificate/authentik-tls` while `authentik-server`, `authentik-worker`, and `authentik-db` were already healthy; `kubectl describe certificate authentik-tls` showed repeated ACME order errors even though the application itself was up.

- Observation: removing home-cluster `authentik` ownership is not only a hostname move; the remaining home apps still need forward-auth.
  Evidence: `clusters/home/overlays/apps/home-assistant.yaml`, `pi-hole.yaml`, and `immich.yaml` all depended on `authentik`, and public checks only stayed healthy after the home Traefik middleware was switched to the Hetzner public Authentik endpoint.

## Decision Log

- Decision: Keep `minecraft` on `perun` during this migration.
  Rationale: The user explicitly asked not to move it yet, and it remains a stateful public workload that deserves a separate storage and backup decision.
  Date/Author: 2026-06-03 / Codex

- Decision: Move apps in four waves: `blog`, then `authentik`, then `glance`, then `paperless`.
  Rationale: `blog` is stateless and proves the edge-app path with minimal risk. `authentik` must land before `glance` and `paperless` because both use its forward-auth middleware. `paperless` is left for last because it has the heaviest storage and data-shape requirements among the chosen Hetzner apps.
  Date/Author: 2026-06-03 / Codex

- Decision: Do not bring Longhorn to Hetzner for this migration.
  Rationale: The current Hetzner plan intentionally keeps the edge cluster lightweight. For single-node Hetzner app data, the default k3s storage class (`local-path`) is sufficient for now, and it avoids reintroducing the heaviest storage control plane just to move a few public apps.
  Date/Author: 2026-06-03 / Codex

- Decision: Add `cnpg` to Hetzner before moving `authentik` and `paperless`.
  Rationale: Both apps already have repository-managed Postgres clusters under `apps/authentik/postgres-cluster.yaml` and `apps/paperless/postgres-cluster.yaml`. Reusing the same operator pattern is safer than inventing ad-hoc databases for Hetzner.
  Date/Author: 2026-06-03 / Codex

- Decision: Keep shared application manifests in `apps/`, but add Hetzner-specific overlay paths where storage class or middleware scope differs from home.
  Rationale: The repo should keep one canonical app definition when possible, but Hetzner must not inherit home-only storage and middleware assumptions.
  Date/Author: 2026-06-03 / Codex

- Decision: Stage Hetzner app reconciliation before removing the same apps from the home cluster.
  Rationale: The public hostnames are still fronted by Cloudflare, so repository ownership and live traffic cutover are not the same operation. Running the apps on Hetzner first de-risks the later routing change.
  Date/Author: 2026-06-03 / Codex

- Decision: Use a Hetzner-specific Authentik wrapper that excludes the managed certificate during the staging phase.
  Rationale: The cluster still needs the Authentik application and outpost for forward-auth, but the certificate should not block reconciliation before traffic cutover is ready.
  Date/Author: 2026-06-03 / Codex

## Outcomes & Retrospective

At plan creation time, the Hetzner cluster already has the minimal edge infrastructure (`flux-system`, `cert-manager`, `cert-manager-issuers`, and `traefik`) running successfully. What is still missing is the actual public application placement. This plan therefore starts from a working base rather than from an empty cluster.

The main lesson from the bootstrap work is that “shared app directory” does not automatically mean “safe for both clusters.” The migration must be explicit about which directories are cluster-neutral and which need Hetzner-specific wrappers.

After the first implementation pass, the repository now contains Hetzner-specific overlay objects for all selected public apps plus Hetzner wrappers for storage and Authentik middleware scope. The live Hetzner cluster now has `blog`, `authentik`, `glance`, `paperless`, `cnpg`, and `traefik-auth` reconciled successfully.

The traffic cutover is now complete. Cloudflare keeps the same public proxy layer, but the tunnel now forwards `def4alt.com`, `auth.def4alt.com`, `dashboard.def4alt.com`, and `papers.def4alt.com` to the Hetzner node origin. The home overlay no longer owns `blog`, `authentik`, `glance`, or `paperless`. The remaining notable operational detail is that home-bound apps such as Home Assistant, Pi-hole, and Immich now authenticate against the public Authentik endpoint hosted on Hetzner rather than a home-local Authentik deployment.

## Context and Orientation

This repository has two independent NixOS hosts and two independent Flux cluster trees.

The NixOS host definitions live in `nixos/flake.nix`. `perun` is the home host and `zorya` is the Hetzner host. The Kubernetes clusters are not one large shared cluster; each host runs its own single-node k3s control plane.

Flux is the GitOps operator that watches a Git repository and applies Kubernetes manifests from selected paths. In this repository, Flux configuration for the home cluster lives under `clusters/home`, and Flux configuration for the Hetzner cluster lives under `clusters/hetzner`. A Flux `Kustomization` object in `clusters/.../overlays/...` tells Flux to apply one directory from `apps/`.

The home cluster currently owns many applications. The current top-level home overlay file `clusters/home/overlays/kustomization.yaml` lists both infrastructure overlays and application overlays. The Hetzner overlay file `clusters/hetzner/overlays/kustomization.yaml` currently contains only minimal infrastructure overlays: namespaces, Cert-Manager, Cert-Manager issuers, and Traefik.

The selected application set is:

- Move to Hetzner: `blog`, `authentik`, `glance`, `paperless`.
- Keep on home: `home-assistant`, `pi-hole`, `immich`, `juicefs`, `cnpg` for home-stateful apps, `longhorn`, `metallb`, `monitoring`, and `minecraft`.

Several app files matter for this migration.

`apps/blog/` is simple: deployment, service, and ingress. It does not depend on Authentik or a database.

`apps/authentik/` is more complex: it includes its Helm release, its own Postgres cluster, and a certificate. The home cluster currently installs it through `clusters/home/overlays/infra/authentik.yaml`. Other apps rely on the Traefik middleware definition in `apps/traefik/middleware-authentik-forward-auth.yaml`, which forwards authentication checks to the embedded Authentik outpost service inside the cluster.

`apps/glance/` is mostly simple, but it has a persistent volume claim in `apps/glance/pvc.yaml` that currently requests `storageClassName: longhorn`. On Hetzner this must be patched to use the cluster default storage instead of Longhorn.

`apps/paperless/` is the heaviest chosen public app. It includes a Postgres cluster, Redis, several deployments, ingress, and a persistent volume claim. Its current home overlay `clusters/home/overlays/apps/paperless.yaml` depends on `cnpg`, `cert-manager`, `authentik`, `longhorn`, and `traefik`. On Hetzner, the `longhorn` dependency must be removed and the volume claim must be patched to the default storage class.

## Plan of Work

First, add a new application overlay directory for Hetzner. Create `clusters/hetzner/overlays/apps/` and add one Flux `Kustomization` file per selected Hetzner app. Update `clusters/hetzner/overlays/kustomization.yaml` so it includes this new `apps/` section after the infrastructure entries. Mirror the home overlay naming style so a novice can compare both cluster trees side by side.

Second, implement Wave 1 for `blog`. Add `clusters/hetzner/overlays/apps/blog.yaml` that points at `./apps/blog` and depends on `namespaces`, `cert-manager`, and `traefik`. Also add `apps/modes/hetzner/namespaces/namespace-blog.yaml` and wire it into `apps/modes/hetzner/namespaces/kustomization.yaml`, because the Hetzner namespace overlay should stay explicit instead of drifting back toward the home namespace set. Once the Hetzner blog overlay is ready, remove `blog` from `clusters/home/overlays/kustomization.yaml` so only one cluster owns it.

Third, prepare Hetzner to host `authentik`. Add `clusters/hetzner/overlays/infra/cnpg.yaml` that points at `./apps/cnpg`, depends on `namespaces`, and uses SOPS decryption like the other encrypted overlays. Add `apps/modes/hetzner/namespaces/namespace-authentik.yaml` and `namespace-cnpg-system.yaml`. Then add `clusters/hetzner/overlays/apps/authentik.yaml` that points at `./apps/authentik` and depends on `cnpg`, `cert-manager-issuers`, and `traefik`.

Because the Hetzner Traefik overlay was intentionally split away from the home middleware objects, add a Hetzner-specific middleware path for Authentik. The simplest shape is a new `apps/modes/hetzner/traefik-auth/` directory that contains only `middleware-authentik-forward-auth.yaml` copied from `apps/traefik/`, or an equivalent minimal kustomization that renders only that middleware. Reconcile that path from a new Hetzner overlay such as `clusters/hetzner/overlays/infra/traefik-auth.yaml`, and make `glance` and `paperless` depend on it indirectly through `authentik` and `traefik`.

Fourth, implement Hetzner `glance`. Add `apps/modes/hetzner/glance/` as a thin wrapper around `apps/glance/` that patches `PersistentVolumeClaim/glance-data` to remove `storageClassName: longhorn`. A patch that sets `storageClassName` to `null` is preferred so k3s can use its default `local-path` storage class. Then add `clusters/hetzner/overlays/apps/glance.yaml` that points at `./apps/modes/hetzner/glance` and depends on `authentik`, `cert-manager`, and `traefik`. Remove the `longhorn` dependency that exists in the home overlay.

Fifth, implement Hetzner `paperless`. Add `apps/modes/hetzner/paperless/` as a thin wrapper around `apps/paperless/`. Patch `PersistentVolumeClaim/paperless-storage` to remove `storageClassName: longhorn`. Keep its Postgres cluster in place, because the app already includes `apps/paperless/postgres-cluster.yaml`, and let it use the cluster default storage unless later evidence shows a need for a dedicated class. Then add `clusters/hetzner/overlays/apps/paperless.yaml` that points at `./apps/modes/hetzner/paperless`, depends on `cnpg`, `cert-manager`, `authentik`, and `traefik`, and explicitly does not depend on `longhorn`.

Sixth, remove Hetzner-owned apps from the home overlay. As each wave is validated on Hetzner, remove the corresponding resource file from `clusters/home/overlays/kustomization.yaml`. The home overlay should end this migration without `blog`, `authentik`, `glance`, or `paperless`. If `authentik` moves, revisit any remaining home apps that still point at `infra-authentik-forward-auth@kubernetescrd` and decide whether they stay private or need a different authentication path.

Seventh, update `README.md` so a novice can see the intended public app ownership immediately. The Kubernetes section should say that the Hetzner cluster now hosts `blog`, `authentik`, `glance`, and `paperless`, while the home cluster keeps `minecraft` and the home-bound data services.

## Concrete Steps

All commands below are run from `/Users/def4alt/source/homelab` unless a different working directory is stated.

Inspect the current cluster overlay structure before editing:

    find clusters/home/overlays -maxdepth 2 -type f | sort
    find clusters/hetzner/overlays -maxdepth 2 -type f | sort

Validate each repository change locally before applying it to the live cluster:

    kubectl kustomize clusters/hetzner >/dev/null
    kubectl kustomize clusters/home >/dev/null

After each wave, verify the live Hetzner cluster from the workstation:

    sshpass -p 'Monetcave243' ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      def4alt@46.62.137.102 \
      "printf '%s\n' Monetcave243 | sudo -S -p '' sh -lc 'k3s kubectl -n flux-system get kustomizations'"

Expected pattern after a successful wave:

    NAME                   READY   STATUS
    flux-system            True    Applied revision: main@sha1:...
    namespaces             True    Applied revision: main@sha1:...
    cert-manager           True    Applied revision: main@sha1:...
    cert-manager-issuers   True    Applied revision: main@sha1:...
    traefik                True    Applied revision: main@sha1:...
    blog                   True    Applied revision: main@sha1:...

To verify application placement at the end, inspect both cluster trees in Git:

    sed -n '1,200p' clusters/hetzner/overlays/kustomization.yaml
    sed -n '1,200p' clusters/home/overlays/kustomization.yaml

And confirm live namespaces on Hetzner stay intentionally small:

    sshpass -p 'Monetcave243' ssh -o PubkeyAuthentication=no -o PreferredAuthentications=password \
      -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null \
      def4alt@46.62.137.102 \
      "printf '%s\n' Monetcave243 | sudo -S -p '' k3s kubectl get ns"

The final Hetzner namespace list should include `flux-system`, `cert-manager`, `infra`, `authentik`, `cnpg-system`, `glance`, and `paperless`, plus the default Kubernetes namespaces. It must not include `minecraft`.

## Validation and Acceptance

Wave 1 is accepted when all of the following are true:

The repository renders `clusters/hetzner` and `clusters/home` without Kustomize errors. The live Hetzner Flux reports `blog` ready. The live home cluster no longer owns the `blog` Kustomization. Visiting `https://def4alt.com` serves from the Hetzner ingress after DNS is updated.

Wave 2 is accepted when `cnpg`, `authentik`, and the Authentik forward-auth middleware are ready on Hetzner, and `https://auth.def4alt.com` serves from the Hetzner cluster.

Wave 3 is accepted when `glance` is ready on Hetzner, its persistent volume claim is bound without Longhorn, and `https://dashboard.def4alt.com` authenticates through Hetzner Authentik.

Wave 4 is accepted when `paperless` is ready on Hetzner, its persistent volume claim is bound without Longhorn, its Postgres cluster is healthy under Hetzner `cnpg`, and `https://papers.def4alt.com` serves from Hetzner through Authentik.

Overall migration acceptance is reached when the home overlay no longer includes `blog`, `authentik`, `glance`, or `paperless`, the Hetzner overlay includes them, and `minecraft` still exists only in the home cluster path.

## Idempotence and Recovery

The overlay edits are GitOps-safe and can be retried. Re-running `kubectl kustomize` is non-destructive. Re-applying Flux bootstrap or waiting for Flux reconciliation is safe.

The risky parts are ownership transitions. If an app is added to Hetzner before it is removed from home, both clusters may try to serve the same hostname. To avoid split-brain behavior, each migration wave should be staged in this order: make the Hetzner manifests render, reconcile the Hetzner app, confirm it is healthy, cut traffic or DNS if needed, then remove the home overlay entry.

If a Hetzner app fails after ownership is removed from home, recover by restoring the corresponding file entry in `clusters/home/overlays/kustomization.yaml`, committing that revert, and waiting for Flux on the home cluster to reconcile.

## Artifacts and Notes

Current live Hetzner baseline before any app migrations beyond infra:

    $ ssh ... zorya "sudo k3s kubectl -n flux-system get kustomizations"
    NAME                   READY   STATUS
    flux-system            True    Applied revision: main@sha1:...
    namespaces             True    Applied revision: main@sha1:...
    cert-manager           True    Applied revision: main@sha1:...
    cert-manager-issuers   True    Applied revision: main@sha1:...
    traefik                True    Applied revision: main@sha1:...

Current home overlay app ownership before this migration:

    clusters/home/overlays/apps/blog.yaml
    clusters/home/overlays/apps/glance.yaml
    clusters/home/overlays/apps/paperless.yaml
    clusters/home/overlays/infra/authentik.yaml

Current Hetzner overlay scope before this migration:

    clusters/hetzner/overlays/infra/namespaces.yaml
    clusters/hetzner/overlays/infra/cert-manager.yaml
    clusters/hetzner/overlays/infra/cert-manager-issuers.yaml
    clusters/hetzner/overlays/infra/traefik.yaml

## Interfaces and Dependencies

The migration relies on these repository interfaces:

`clusters/home/overlays/kustomization.yaml` and `clusters/hetzner/overlays/kustomization.yaml` are the top-level ownership maps for each cluster. If an app is present in one of these files, Flux for that cluster will reconcile it.

`clusters/.../overlays/*.yaml` files are Flux `Kustomization` objects. Each one must set `spec.path` to a directory under `apps/`, `spec.sourceRef.name` to `flux-system`, and `spec.dependsOn` to the smallest correct dependency set.

`apps/modes/hetzner/...` is the approved place for Hetzner-specific wrappers and patches. Use it whenever the home app definition bakes in storage, middleware, or networking assumptions that are not valid on the Hetzner edge cluster.

`apps/cnpg/` is the shared CloudNativePG operator path. A CloudNativePG operator is the controller that manages Postgres clusters from declarative YAML. Hetzner needs this operator before `authentik` or `paperless` can use their existing `postgres-cluster.yaml` files.

`apps/traefik/middleware-authentik-forward-auth.yaml` defines the Traefik forward-auth object that later apps use in ingress annotations. On Hetzner, only the Authentik middleware should be reintroduced; the Pi-hole redirect middleware must stay excluded.

Change note: Initial plan created to move selected public apps (`blog`, `authentik`, `glance`, `paperless`) to the Hetzner cluster while explicitly keeping `minecraft` on the home cluster.
Change note: Updated after adding the Hetzner app overlay scaffolding and discovering that Cloudflare-proxied public DNS requires staged deployment before removing home-cluster ownership.
Change note: Updated after the first live Hetzner app rollout to exclude the Authentik certificate from staged reconciliation so application health can converge before public cutover.
Change note: Updated after the staged Hetzner app set (`blog`, `authentik`, `glance`, `paperless`) reconciled successfully and the README was revised to describe the split and the remaining traffic-cutover step.
Change note: Updated after Cloudflare cutover and home-overlay pruning completed, with home protected apps switched to the Hetzner Authentik public endpoint.
