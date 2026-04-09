# Package the Go blog for the homelab and wire it into Flux

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

## Purpose / Big Picture

After this change, the blog can run as a container in the homelab and be managed entirely through FluxCD. A browser should be able to reach the site at `https://def4alt.com`, the app should answer a simple health check for Kubernetes probes, and the homelab repository should contain the namespace, app manifests, Flux wiring, DNS entry, and dashboard link needed to keep the service discoverable and reproducible.

The blog application itself lives in the sibling repository `/Users/def4alt/source/def4alt.com`. That repository already renders Markdown posts on the server and serves assets from `content/`, `templates/`, and `static/`. This change will package those files into an image, then add the Kubernetes and Flux resources in this repository so the homelab can deploy it like the other services.

## Progress

- [x] (2026-04-09 08:00Z) Inspect the blog app repository and the homelab Flux layout to confirm where the container, namespace, app manifests, and cluster overlays belong.
- [x] (2026-04-09 10:25Z) Add a production container image for the blog app, including a local HTMX asset and a `/healthz` endpoint for probes.
- [x] (2026-04-09 10:25Z) Add the `blog` namespace and the `apps/blog` Kubernetes manifests in the homelab repository.
- [x] (2026-04-09 10:25Z) Wire the new app into the Flux overlay tree under `clusters/home/overlays`.
- [x] (2026-04-09 10:45Z) Add the apex blog hostname to Cloudflare DNS management and the Glance dashboard links.
- [x] (2026-04-09 10:45Z) Validate the app build and the Kubernetes manifests locally; validate the runtime by starting the compiled binary and curling `/healthz`.
- [x] (2026-04-09 10:55Z) Commit the changes in small, reviewable Git commits.

## Surprises & Discoveries

- Observation: The homelab repo already uses Flux `Kustomization` overlays under `clusters/home/overlays/apps/*.yaml`, with matching app directories under `apps/<name>`.
  Evidence: `clusters/home/overlays/kustomization.yaml` lists existing app overlays like `apps/glance.yaml`, and `apps/glance/kustomization.yaml` shows the per-app pattern.
- Observation: The blog app currently reads Markdown, templates, and static files from the filesystem at runtime, so container packaging only needs to copy those directories into the image.
  Evidence: `def4alt.com/internal/content/loader.go` and `def4alt.com/internal/render/render.go` both read from relative paths.
- Observation: The homelab already has Cloudflare DNS management in Terraform, so adding the blog hostname there will keep the public name consistent with the rest of the stack.
  Evidence: `cloudflare/locals.tf` defines the managed hostnames set used by `cloudflare_record.cname`.

- Observation: The local Docker daemon was unavailable in this environment, so the container build could not be exercised directly here.
  Evidence: `docker build -t def4alt-blog:local .` returned `Cannot connect to the Docker daemon`; the compiled binary was validated by running it directly and curling `http://127.0.0.1:9091/healthz`.

## Decision Log

- Decision: Use the root hostname `def4alt.com` as the public hostname for the new service.
  Rationale: The user wants the blog at the apex domain instead of a subdomain, and Cloudflare can flatten the apex CNAME while the rest of the stack continues to use subdomains.
  Date/Author: 2026-04-09 / Codex

- Decision: Keep the first version simple and do not add a database or extra secrets.
  Rationale: The blog already stores its content in Markdown files, so the container only needs to ship the compiled binary and static site files.
  Date/Author: 2026-04-09 / Codex

- Decision: Add a dedicated `/healthz` endpoint to the blog app and point Kubernetes probes at it.
  Rationale: Health checks should be stable and inexpensive; using the homepage would couple infrastructure checks to content rendering.
  Date/Author: 2026-04-09 / Codex

- Decision: Self-host HTMX from the blog container instead of loading it from a CDN.
  Rationale: The homelab should remain usable without depending on an external JavaScript host.
  Date/Author: 2026-04-09 / Codex

- Decision: Use `ghcr.io/def4alt/blog:latest` for the initial homelab Deployment image.
  Rationale: There is no release pipeline yet, so a fixed `latest` reference keeps the first deployment simple while still leaving room for later image automation or semver tagging.
  Date/Author: 2026-04-09 / Codex

## Outcomes & Retrospective

Complete. The blog now has a container packaging story and the homelab repo has the Kubernetes and Flux wiring needed to deploy it as `def4alt.com`. The app responds to `/healthz`, serves HTMX locally from `static/htmx.min.js`, and can be built and run directly from the sibling repository. The homelab manifests are in place and `kustomize build` succeeds for both `apps/blog` and `clusters/home/overlays`.

The only local limitation was the Docker daemon. That meant the image itself was not built in this environment, but the Dockerfile is aligned with the runtime layout that was already verified by the direct binary run. A follow-up could add image automation or release tagging once there is a preferred build pipeline.

## Context and Orientation

The blog application repo is `/Users/def4alt/source/def4alt.com`. It exposes a Go HTTP server in `cmd/main.go`, loads Markdown posts from `content/posts/*.md`, renders templates from `templates/`, and serves static assets from `static/`. The homelab repo is `/Users/def4alt/source/homelab`. Its Kubernetes resources live under `apps/`, and Flux entrypoints for the home cluster live under `clusters/home/overlays/`.

A Flux `Kustomization` in this repo usually points at one directory under `apps/<name>`. That app directory normally contains the namespace-scoped resources for the service. The root `clusters/home/overlays/kustomization.yaml` must reference both the namespace overlay and the app overlay. DNS records for public services are managed in `cloudflare/locals.tf`, and the Glance dashboard uses `apps/glance/configmap.yaml` to define shortcut links.

The blog does not need a database, persistent volume, or application secret. It does need a container image, a namespace, a Deployment, a Service, an Ingress, and a Flux overlay. The Deployment should use the blog image built from the sibling repository and should expose port 8080, matching the Go server.

## Plan of Work

First, update the blog application repository so it can be deployed cleanly in Kubernetes. Add a `/healthz` route and test it in `internal/handler/routes_test.go`, then implement the handler in `internal/handler/handler.go` and register it in `internal/handler/routes.go`. Replace the HTMX CDN reference in `templates/layouts/base.html` with a local file under `static/htmx.min.js`, and add that file to the blog repo. Add a `Dockerfile` at the repository root that builds the Go binary and copies `cmd/`, `content/`, `static/`, and `templates/` into a small runtime image. Add a `.dockerignore` if needed to keep the build context small.

Next, add the homelab resources for the blog under `apps/blog`. Create `apps/blog/kustomization.yaml`, `deployment.yaml`, `service.yaml`, and `ingress.yaml` for a single replica that listens on port 8080, exposes HTTP through Traefik, and uses the blog image from the registry. Add `apps/namespaces/namespace-blog.yaml` and include it from `apps/namespaces/kustomization.yaml`. Add `clusters/home/overlays/apps/blog.yaml` so Flux reconciles the new app, and include that overlay from `clusters/home/overlays/kustomization.yaml`.

Finally, add the external references that make the service visible in the rest of the stack. Update `cloudflare/locals.tf` so the blog hostname is managed by Terraform, update `apps/glance/configmap.yaml` to add a blog shortcut, and update `README.md` to document the new service in the homelab stack.

## Concrete Steps

Work from two directories as needed:

- `/Users/def4alt/source/def4alt.com` for the blog application changes.
- `/Users/def4alt/source/homelab` for Flux, Kubernetes, Cloudflare, and documentation changes.

The implementation order should be:

1. Add the `/healthz` test in the blog repo and verify it fails before the handler exists.
2. Implement the health handler and route, then rerun `go test ./...` in the blog repo.
3. Download or vendor `htmx.min.js`, update the base template to load it locally, and add the `Dockerfile`.
4. Create the `apps/blog` manifests and namespace in the homelab repo.
5. Wire the new app into `clusters/home/overlays`.
6. Update Cloudflare DNS, Glance, and the README.
7. Validate with `go test ./...` in the blog repo, `go build ./cmd` or `docker build` for the blog image, and `kustomize build` for the homelab app and overlay trees.

## Validation and Acceptance

The change is complete when all of the following are true:

- In the blog repo, `go test ./...` passes, and `curl http://localhost:8080/healthz` returns HTTP 200 with body `ok` when the server runs.
- A container built from the blog repo starts successfully and serves the homepage from its copied content/template files.
- In the homelab repo, `kustomize build apps/blog` produces valid Kubernetes YAML for the namespace-scoped blog resources.
- In the homelab repo, `kustomize build clusters/home/overlays` succeeds and includes the new blog overlay.
- `cloudflare/locals.tf` contains the new hostname, and `apps/glance/configmap.yaml` shows a blog shortcut.
- The README mentions the blog as a managed service in the homelab stack.

## Idempotence and Recovery

All changes should be additive. If a manifest or template change needs to be redone, the safest rollback is to revert the last Git commit in the affected repository and reapply the plan step. The blog image build should not mutate any source files. The homelab manifests should remain valid even if Flux has not yet reconciled them.

## Artifacts and Notes

The key artifacts expected from this change are:

- `/Users/def4alt/source/def4alt.com/Dockerfile`
- `/Users/def4alt/source/def4alt.com/static/htmx.min.js`
- `/Users/def4alt/source/def4alt.com/internal/handler/routes_test.go`
- `/Users/def4alt/source/homelab/apps/blog/*`
- `/Users/def4alt/source/homelab/apps/namespaces/namespace-blog.yaml`
- `/Users/def4alt/source/homelab/clusters/home/overlays/apps/blog.yaml`
- `/Users/def4alt/source/homelab/cloudflare/locals.tf`
- `/Users/def4alt/source/homelab/apps/glance/configmap.yaml`
- `/Users/def4alt/source/homelab/README.md`

## Interfaces and Dependencies

The blog app should continue to expose the Go HTTP server on port 8080. The new health route should be named `/healthz` and should return a plain `200 OK` response with body `ok`. The container image should include the compiled binary plus the `content/`, `templates/`, and `static/` directories required by the current runtime file loading.

The homelab Deployment should reference the blog image in the registry and expose container port 8080. The Service should route port 80 to target port 8080. The Ingress should use Traefik and cert-manager like the other public services in this repo, and it should not require the Authentik forward-auth middleware unless the blog is intentionally made private later.

Change note: Initial plan created after confirming the blog app and homelab repos are separate and that the homelab already uses Flux overlays under `clusters/home/overlays`.
