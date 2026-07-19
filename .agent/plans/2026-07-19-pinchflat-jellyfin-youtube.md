# Add a Pinchflat YouTube library to Jellyfin

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds. Maintain this document in accordance with `.agent/PLANS.md` from the repository root.

## Purpose / Big Picture

After this change, the user can manage YouTube channel and playlist downloads at `https://yt.def4alt.com` without browsing YouTube, and downloaded media is available to the existing Jellyfin server under `/media/youtube`. Pinchflat performs downloads and writes media-center metadata; Jellyfin reads the resulting files without permission to alter them. The deployment is managed by Flux from this repository and uses retained single-node storage.

## Progress

- [x] (2026-07-19 15:50Z) Inspected the existing Flux, local-storage, Jellyfin, Traefik, Authentik, and Cloudflare patterns.
- [x] (2026-07-19 15:50Z) Selected Pinchflat and recorded storage, access, security, and hostname decisions.
- [x] (2026-07-19 15:58Z) Added the Pinchflat application, retained storage, Authentik-protected ingress, and Flux wiring.
- [x] (2026-07-19 16:05Z) Mounted downloaded media read-only in Jellyfin and created its `YouTube` TV Shows library at `/media/youtube/shows`.
- [x] (2026-07-19 15:53Z) Applied Cloudflare DNS and Tunnel routing for `yt.def4alt.com`; OpenTofu reported one addition, one in-place change, and no destruction.
- [x] (2026-07-19 16:00Z) Validated rendered manifests with client and server dry-runs and validated the OpenTofu configuration; the Cloudflare plan was exactly one add and one in-place change.
- [x] (2026-07-19 16:06Z) Committed and pushed revision `5f163d3`, reconciled Flux, and verified the live service, storage, ingress, certificate, health endpoint, and Jellyfin mount.
- [x] (2026-07-19 16:01Z) Created Pinchflat's `TV Shows` profile from its Media Center preset without adding sources that could unexpectedly fill the disk.

## Surprises & Discoveries

- Observation: The host filesystem has about 183 GiB free even though existing hostPath volume capacities sum to more than that.
  Evidence: `kubectl exec -n transmission deploy/jellyfin -- df -h /media/transmission` reported 183 GiB available. Kubernetes hostPath capacities are declarations and do not enforce quotas.
- Observation: Pinchflat has a native `/healthcheck` endpoint and recommends a Media Center profile for Jellyfin, but does not directly configure Jellyfin.
  Evidence: The upstream container Dockerfile uses `/healthcheck`; its FAQ says media-center integration is file naming and metadata rather than an application API integration.
- Observation: The home Authentik provider deliberately uses `photos.def4alt.com` as its callback host for all protected home domains.
  Evidence: An anonymous request to `yt.def4alt.com` returned HTTP 302 with the final target preserved as `yt.def4alt.com` in state and `redirect_uri` set to the existing home outpost callback at `photos.def4alt.com`; this matches the documented home callback topology.
- Observation: The Kubernetes API briefly refused a verification request while the node remained pingable, then recovered without intervention.
  Evidence: One `kubectl get` returned connection refused; three seconds later the node was Ready and all three affected Flux Kustomizations were Ready at revision `5f163d3`.

## Decision Log

- Decision: Deploy Pinchflat rather than Tube Archivist or MeTube.
  Rationale: Pinchflat is a single-container application designed for channel and playlist synchronization and media-center metadata, while Tube Archivist is substantially heavier and MeTube lacks subscription management.
  Date/Author: 2026-07-19 / coding agent
- Decision: Deploy Pinchflat in the existing `transmission` media namespace.
  Rationale: Jellyfin and the existing media automation applications already share this namespace, allowing a single ReadWriteOnce hostPath claim to be mounted by both workloads on the one-node cluster.
  Date/Author: 2026-07-19 / coding agent
- Decision: Use separate retained hostPath volumes for Pinchflat configuration and YouTube media, declaring 2 GiB and 100 GiB respectively.
  Rationale: Separate storage keeps application state and replaceable media distinct. A 100 GiB declaration is conservative given current free space, though hostPath does not enforce the declared capacity.
  Date/Author: 2026-07-19 / coding agent
- Decision: Publish the management UI as `yt.def4alt.com` behind the existing Authentik forward-auth middleware.
  Rationale: The hostname is concise and the UI controls unrestricted downloads, so it must not be anonymously accessible.
  Date/Author: 2026-07-19 / coding agent
- Decision: Run one yt-dlp worker and run the application as UID/GID 1000 after an init container prepares volume ownership.
  Rationale: One worker reduces YouTube rate-limit and disk pressure. A non-root process follows least privilege while matching the media ownership used elsewhere.
  Date/Author: 2026-07-19 / coding agent

## Outcomes & Retrospective

Pinchflat is deployed and healthy at the Authentik-protected `https://yt.def4alt.com`. Configuration and media are retained on dedicated hostPath volumes, Pinchflat runs as UID/GID 1000 with one download worker, and its `TV Shows` profile uses the upstream Media Center preset at 1080p while excluding Shorts and livestreams. No source was added, intentionally preventing an unbounded historical download.

Jellyfin has the shared volume mounted read-only and a `YouTube` TV Shows library configured at `/media/youtube/shows`. A live write test succeeded from Pinchflat and failed from Jellyfin as intended. The in-cluster Pinchflat health check returned HTTP 200, the public endpoint redirected to Authentik, the TLS certificate became Ready, and Flux applied revision `5f163d3` for local storage, Pinchflat, and Jellyfin. The only remaining user choice is which channels or playlists to add and what per-source historical cutoff or retention to use.

## Context and Orientation

The repository is a GitOps configuration for a one-node k3s cluster named `perun`. Flux watches `main` and applies application directories selected by `clusters/home/overlays/kustomization.yaml`. `apps/local-storage` declares retained Kubernetes PersistentVolumes backed by directories below `/var/lib/k8s-local-storage` on `perun`. A PersistentVolume is a storage resource, and a PersistentVolumeClaim is an application's request to mount that resource.

Jellyfin is defined in `apps/jellyfin` and runs in the `transmission` namespace. Its deployment already reads Transmission media and exposes `/dev/dri` for hardware transcoding. Pinchflat will be defined in `apps/pinchflat`, also in `transmission`. It will mount `pinchflat-config` read/write at `/config` and `youtube-media` read/write at `/downloads`. Jellyfin will mount `youtube-media` read-only at `/media/youtube`.

Traefik serves Kubernetes Ingress resources. Authentik's forward-auth middleware is named `infra-authentik-forward-auth@kubernetescrd`; attaching it to the Pinchflat Ingress requires successful authentication before requests reach Pinchflat. Cloudflare configuration in `cloudflare/locals.tf` determines which public hostnames receive DNS records and Tunnel ingress routes.

## Plan of Work

Create `apps/pinchflat` with a Kustomization, two claims, a Deployment, a Service, and an Ingress. The Deployment uses the digest-pinned upstream image, health probes against `/healthcheck`, conservative resource settings, one yt-dlp worker, and a root init container that gives UID 1000 ownership of the mounted directories. The main container drops Linux capabilities and runs as UID/GID 1000.

Add `apps/local-storage/pinchflat.yaml` with retained hostPath volumes and include it from `apps/local-storage/kustomization.yaml`. Add `clusters/home/overlays/apps/pinchflat.yaml` and include it from the home overlay so Flux reconciles the application after namespaces, storage, and authentication middleware are ready.

Modify `apps/jellyfin/deployment.yaml` to mount the YouTube claim read-only. Add `yt.def4alt.com` to `cloudflare/locals.tf`, causing existing generic resources to create the proxied CNAME and Tunnel route. Update the root README application inventory.

Render the affected Kustomizations with `kubectl kustomize`, validate client-side with `kubectl apply --dry-run=client`, run `tofu fmt -check` and `tofu validate`, and check whitespace with `git diff --check`. Commit only task files, leaving the pre-existing untracked `CONTEXT.md` untouched, push `main`, reconcile Flux, and inspect workloads, claims, ingress, certificate, and health endpoint.

After deployment, add `/media/youtube/shows` to Jellyfin as a TV Shows library if authenticated API access is available. If Pinchflat has not yet created `shows`, create it in the shared volume first. Configure Pinchflat through the UI with its Media Center preset before adding sources; source creation is intentionally not automated because selecting retention and whether old channel history should download controls potentially large disk usage.

## Concrete Steps

From `/Users/def4alt/src/github.com/def4alt/homelab`, create and edit the files described above. Then run:

    kubectl kustomize apps/local-storage >/tmp/local-storage.yaml
    kubectl kustomize apps/pinchflat >/tmp/pinchflat.yaml
    kubectl kustomize apps/jellyfin >/tmp/jellyfin.yaml
    kubectl kustomize clusters/home/overlays >/tmp/home-overlays.yaml
    kubectl apply --dry-run=client -f /tmp/pinchflat.yaml
    kubectl apply --dry-run=client -f /tmp/jellyfin.yaml
    nix develop -c tofu -chdir=cloudflare fmt -check
    nix develop -c tofu -chdir=cloudflare validate
    git diff --check

Commit and push the intended paths, then request immediate reconciliation:

    git add .agent/plans/2026-07-19-pinchflat-jellyfin-youtube.md apps/pinchflat apps/local-storage/pinchflat.yaml apps/local-storage/kustomization.yaml apps/jellyfin/deployment.yaml clusters/home/overlays/apps/pinchflat.yaml clusters/home/overlays/kustomization.yaml cloudflare/locals.tf README.md
    git commit -m 'feat(media): add Pinchflat YouTube library'
    git push origin main
    nix develop -c flux reconcile source git flux-system -n flux-system
    nix develop -c flux reconcile kustomization local-storage -n flux-system --with-source
    nix develop -c flux reconcile kustomization pinchflat -n flux-system --with-source
    nix develop -c flux reconcile kustomization jellyfin -n flux-system --with-source

Expected live evidence includes a Ready `pinchflat` Flux Kustomization, Bound `pinchflat-config` and `youtube-media` claims, a Ready Pinchflat pod, HTTP 200 from `/healthcheck` inside the cluster, and `/media/youtube` mounted read-only in Jellyfin.

Cloudflare is managed separately from Flux. Preview and apply only the hostname addition:

    nix develop -c tofu -chdir=cloudflare plan
    nix develop -c tofu -chdir=cloudflare apply

The plan should add one proxied DNS record and one Tunnel hostname rule for `yt.def4alt.com`, subject to the existing `manage_dns` and `manage_tunnel_config` variable values.

## Validation and Acceptance

Static acceptance requires all four Kustomizations to render without errors, both application manifests to pass Kubernetes client dry-run, OpenTofu validation to succeed, and `git diff --check` to report nothing.

Live Kubernetes acceptance requires `kubectl get kustomization pinchflat jellyfin local-storage -n flux-system` to show `READY=True`; `kubectl get deploy,pod,svc,ingress,pvc -n transmission` to show Pinchflat Ready and both new claims Bound; and the following command to return `200`:

    kubectl run pinchflat-health --rm -i --restart=Never --image=curlimages/curl -- curl -sS -o /dev/null -w '%{http_code}\n' http://pinchflat.transmission.svc.cluster.local:8945/healthcheck

`kubectl exec -n transmission deploy/jellyfin -- sh -c 'test -d /media/youtube && touch /media/youtube/write-test'` must fail at the `touch`, proving Jellyfin cannot alter downloads. Pinchflat must be able to create `/downloads/shows`, proving it can write the shared volume.

User-visible acceptance is that `https://yt.def4alt.com` reaches Authentik and then Pinchflat, and Jellyfin can add `/media/youtube/shows` as a TV Shows library. A Media Center profile and at least one source must be configured before a downloaded episode can demonstrate metadata and playback.

## Idempotence and Recovery

Kustomize rendering, dry-runs, Flux reconciliation, and OpenTofu planning are safe to repeat. The init container's `mkdir` and `chown` operations are idempotent. PersistentVolumes use `Retain`, so removing the application does not erase configuration or downloads. To roll back the workload, revert the Git commit and reconcile Flux; manually delete retained claims or host directories only when deliberately discarding data.

Do not configure all 32 existing subscriptions to download full history at once. The host has limited free space and hostPath capacity declarations do not impose quotas. Start with a restrictive date cutoff, item limit, or retention policy in Pinchflat, observe disk usage, and then add sources incrementally.

## Artifacts and Notes

The selected Pinchflat image is `ghcr.io/kieraneglin/pinchflat:latest@sha256:01b4f98aabaf3f5fe394213f7a32578c9e84e42080f52e2f8334021a4473b202`, resolved from GHCR on 2026-07-19. Pinchflat listens on port 8945 and its unauthenticated health endpoint is `/healthcheck`.

Current storage evidence before deployment was:

    Filesystem      Size  Used Avail Use% Mounted on
    /dev/nvme0n1p2  931G  743G  183G  81% /media/transmission

## Interfaces and Dependencies

Pinchflat exposes HTTP port 8945 through a ClusterIP Service named `pinchflat`. Its Ingress hostname is `yt.def4alt.com`. The application requires writable `/config` and `/downloads` mounts and outbound HTTPS access to YouTube and related media hosts. It stores its own SQLite database in `/config`; no external database or secret is needed because Authentik protects the UI.

The shared storage interface is the `youtube-media` claim in namespace `transmission`. Pinchflat owns writes; Jellyfin receives a read-only mount at `/media/youtube`. The intended Jellyfin library root produced by Pinchflat's Media Center preset is `/media/youtube/shows`.

Revision note (2026-07-19): Created the initial plan after repository and live-cluster discovery; selected conservative storage and one-worker defaults because only about 183 GiB is currently free.

Revision note (2026-07-19 16:00Z): Recorded completion of declarative implementation and static validation. The server accepted all resources in dry-run, and OpenTofu planned one DNS record addition plus one Tunnel configuration update with no destruction.

Revision note (2026-07-19 16:06Z): Recorded final live outcomes: Flux convergence, healthy Pinchflat, writable/read-only storage roles, ready TLS and public Authentik routing, the Media Center profile, and the Jellyfin library. Sources remain intentionally unconfigured to avoid an uncontrolled historical download.
