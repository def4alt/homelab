## Exec Plan: flux-based homelab deployment

**Goal:** Deploy a k3s-based homelab stack on Debian with FluxCD managing Traefik, Cloudflared, Kan, Pi-hole, Longhorn, Paperless-ngx, Nextcloud, and Home Assistant per the latest FluxCD documentation.

### Step 1 – Gather context and requirements
- Status: completed
- Identify the relevant FluxCD documentation via Context7, note compatibility considerations with k3s, and capture any cluster prerequisites (e.g., storage, ingress, certificates).
- Notes:
  - The official Flux install guide emphasizes using the `flux` CLI (install script at https://raw.githubusercontent.com/fluxcd/flux2/main/install/flux.sh) to bootstrap clusters, which aligns well with k3s on Debian.
  - Bootstrap flow creates Flux controllers, configures Git repositories, and optionally deploys extra components (see https://fluxcd.io/flux/installation/). We'll rely on this to install the base Flux components before layering our services.
  - Flux documentation also highlights managing optional components (e.g., Multi-tenancy, workload identity) through configuration once bootstrap is complete, so we'll prepare a Git repo layout that separates core infrastructure (Traefik, Longhorn, networking) from application overlays.

### Step 2 – Design GitOps layout
- Status: in_progress
- Define repository structure for Flux components, kustomizations, and service overlays; choose namespaces, configure secret management (e.g., sealed secrets or Flux-managed secrets), and determine how each service will be provisioned.
- Notes:
  - Plan to follow a layered layout: `clusters/home` holds cluster-specific `GitRepository` and `Kustomization` definitions that bootstrap `flux-system`, and `apps/{service}` directories contain base kustomizations (this mirrors the flux bootstrap pattern described at https://fluxcd.io/flux/installation/).
  - Each major component (Traefik, Cloudflared tunnel agent, Tailscale, Longhorn storage class, Kan, Pi-hole, Paperless-ngx, Nextcloud, Home Assistant) will live in `apps/` as its own kustomization so Flux can sync them independently; `clusters/home/overlays` will tie them together via Kustomization ordering.
  - Secret handling will use `sops` to encrypt YAML/JSON secrets stored under `apps/{service}/secrets`, keeping credentials out of plaintext manifests while allowing Flux to decrypt them via a shared key.
-  - Namespaces: `flux-system`, `infra` (traefik, cloudflared, longhorn), and one namespace per consumer app (`kan`, `pi-hole`, `paperless`, `nextcloud`, `home-assistant`) to align with the guiding principle of multi-namespace clarity in flux docs.
-  - Overlay strategy: keep each service in `apps/{service}` and let `clusters/home/overlays` control ordering—infra overlay applies Traefik → Cloudflared → Tailscale → Longhorn → Restic, then each app overlay references its service kustomization so Flux can reconcile infra independently and promote/rollback apps individually; umbrella overlays can still be built later if grouped promotions are desirable.
- Service-specific requirements:
  - **Traefik (infra namespace)**: install via Helm chart to replace the default k3s ingress, enable HTTPS (ACME via Cloudflare DNS token stored in sealed secrets), configure routers for app hosts, expose dashboard, and watch Cloudflared tunnel ingress definitions for domain handoff.
  - **Cloudflared tunnel agent (infra namespace)**: deploy with tunnel credentials stored via Flux-managed secrets, mount a config.yaml for `ingress` rules pointing at Traefik service endpoints, and add readiness/liveness probes to keep the tunnel active.
  - **Tailscale (infra namespace)**: use the official or community chart to run the daemonset, provide the auth key as a secret, enable MagicDNS for internal service discovery, and consider extra tags/policies needed by the apps.
  - **Longhorn (infra namespace)**: install with k3s-friendly values (e.g., disable CSI driver conflict, set replica count to 2), ensure default StorageClass is `longhorn`, and plan for backup storage later; applications request PVs from this class.
  - **Restic backup operator (infra namespace)**: deploy a Restic CronJob/DaemonSet or Velero-style installation configured to snapshot the namespace volumes (ideally whole app data dirs on Longhorn) and push to Backblaze B2 (S3-compatible) storage, managing B2 credentials via Flux secrets and scheduling regular full/incremental backups.
  - **Kan (kan namespace)**: requires database (Postgres) credentials, Longhorn volumes for uploads, Traefik ingress with TLS, and optional Cloudflare/Tailscale access for API/web UI.
  - **Pi-hole (pi-hole namespace)**: persistent volumes for `/etc/pihole` and `/etc/dnsmasq.d` (Longhorn), environment secrets for DNS settings and admin password, Traefik routes for web UI, and Tailscale/Cloudflared exposure for DNS clients.
  - **Paperless-ngx (paperless namespace)**: needs PostgreSQL/Redis (could be bundled via Helm chart dependencies or separate apps), media volumes on Longhorn, secrets for user credentials and encryption keys, and Traefik ingress with TLS certificate secrets.
  - **Nextcloud (nextcloud namespace)**: requires MariaDB/PostgreSQL and Redis backends, Longhorn PVs for `data/`, `config/`, and `apps/`, a strong admin password stored in secrets, and Traefik ingress with Cloudflare-managed TLS for the user-facing domain.
  - **Home Assistant (home-assistant namespace)**: persistent `/config` volume on Longhorn, run on host networking so Zigbee stick/devices remain discoverable while Traefik/Tailscale still manage access, secrets for `HA_KEY`, `LONG_LIVED_TOKEN`, and webhook passwords, and connection info for optional add-ons (MQTT, DuckDNS, etc.).

### Step 3 – Implement base infrastructure
- Status: pending
- Bootstrap Flux on the k3s Debian host, install required custom resources, configure Traefik ingress and Cloudflared tunnel integration, deploy Tailscale for private networking, ensure Longhorn storage is provisioned, and deploy Restic-based backups to Backblaze B2.

### Step 4 – Deploy applications
- Status: pending
- Create Flux-managed manifests/kustomizations for Kan, Pi-hole, Paperless-ngx, Nextcloud, and Home Assistant, wiring ingress routes through Traefik with Cloudflared DNS.

### Step 5 – Verification and documentation
- Status: pending
- Validate deployments, confirm services reachable via intended domains, document setup steps, and note any follow-up actions (monitoring, backups, upgrades).

**Notes:** Will update this Exec Plan with progress and decisions; no manifests created yet in accordance with the instruction to plan before coding.
