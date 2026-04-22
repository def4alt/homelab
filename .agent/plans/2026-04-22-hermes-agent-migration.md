# Hermes Agent Migration Implementation Plan

> **For implementation:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the existing nanobot Telegram bot with Hermes Agent in the `ai` namespace, using the same Telegram bot credentials and allowlist, then remove the nanobot deployment entirely.

**Architecture:** Hermes will run as the official `nousresearch/hermes-agent` container in a single Deployment with a persistent `/opt/data` volume, exactly like the image’s Docker documentation expects. The Telegram bot token and allowlist stay in a SOPS-managed Secret, and the container will read them as environment variables. The Flux overlay will point at the new app path so reconciliation deploys Hermes instead of nanobot, and the old nanobot manifests will be removed so only one Telegram bot owns the token.

**Tech Stack:** Kubernetes manifests, Flux `Kustomization`, Kustomize overlays, SOPS-encrypted Kubernetes Secret, official Hermes Agent Docker image.

---

## Purpose / Big Picture

Today the `ai` namespace runs `nanobot`, which is a custom agent built around a Telegram bot token, an allowlist, and a persistent data volume. After this migration, that Telegram bot will be Hermes Agent instead. From the user’s point of view, the same Telegram bot identity will keep working, but the backend will be Hermes and the nanobot manifests will be gone from the repo.

The key user-visible proof is simple: after Flux reconciles the change, the bot should come online under Hermes, answer messages only from the allowed Telegram user ID(s), and the old nanobot Deployment should no longer exist in the cluster.

## Progress

- [x] (2026-04-22 00:00Z) Read the project instructions and identified that this change touches multiple manifests and should be tracked as an ExecPlan.
- [x] (2026-04-22 00:00Z) Reviewed the existing `apps/nanobot` deployment pattern, the `ai` namespace, and the Flux overlay structure.
- [x] (2026-04-22 00:00Z) Reviewed Hermes docs for Docker, configuration, Telegram messaging, and security. Confirmed the gateway health endpoint is `/health` and Telegram allowlisting uses `TELEGRAM_ALLOWED_USERS`.
- [x] (2026-04-22 18:57Z) Create `apps/hermes-agent` manifests that use the native Hermes container image, `/opt/data` volume, and Hermes API server health checks instead of the nanobot-specific bootstrap logic.
- [x] (2026-04-22 18:57Z) Reuse the existing nanobot secret values in a new Hermes SOPS secret file so the Telegram bot token and allowlist continue to work without introducing new plaintext secrets.
- [x] (2026-04-22 18:57Z) Update the Flux overlay to reconcile Hermes instead of nanobot, and remove the old nanobot overlay entry.
- [x] (2026-04-22 18:57Z) Delete the nanobot app manifests so the cluster no longer carries two competing Telegram bot deployments.
- [x] (2026-04-22 18:57Z) Validate the rendered manifests with Kustomize; both the app overlay and the cluster overlay render successfully.
- [x] (2026-04-22 18:57Z) Reconcile Flux in-cluster and confirm the Hermes Deployment became Ready while the nanobot workload disappeared.

## Surprises & Discoveries

- Observation: Hermes’ official Docker image expects its writable data under `/opt/data`, and its entrypoint bootstraps `config.yaml`, `.env`, `SOUL.md`, sessions, memories, and skills there.
  Evidence: `website/docs/user-guide/docker.md` and `docker/entrypoint.sh` in the Hermes repository.
- Observation: Hermes gateway health is served on `/health`, but the API server must be explicitly enabled with `API_SERVER_ENABLED=true` before that endpoint appears.
  Evidence: `gateway/platforms/api_server.py` and `gateway/config.py`.
- Observation: Kubernetes HTTP probes hit the pod IP, while Hermes' API server defaults to loopback; an exec probe against `127.0.0.1:8642/health` keeps the deployment native without adding an auth key.
  Evidence: the first rollout only became Ready after switching to exec probes and enabling the API server.
- Observation: Telegram allowlisting is explicit and simple; the repo uses `TELEGRAM_ALLOWED_USERS` for platform-specific gating.
  Evidence: `website/docs/user-guide/messaging/telegram.md` and `website/docs/user-guide/security.md`.
- Observation: The Hermes gateway can be started natively with the CLI subcommand `hermes gateway`, and the official container entrypoint hands those args to the Hermes binary after bootstrapping `/opt/data`.
  Evidence: `hermes_cli/gateway.py`, `scripts/hermes-gateway`, and the Docker docs.
- Observation: `kubectl kustomize` is available in this environment even though the standalone `kustomize` binary is not installed.
  Evidence: `kustomize: command not found` followed by successful `kubectl kustomize apps/hermes-agent` and `kubectl kustomize clusters/home/overlays`.

## Decision Log

- Decision: Deploy Hermes in the `ai` namespace rather than creating a new namespace.
  Rationale: nanobot already lives there, and Hermes is a direct replacement for the same conversational assistant role.
  Date/Author: 2026-04-22 / Codex
- Decision: Reuse the current nanobot credential values for Hermes, but store them in a Hermes-specific SOPS Secret file.
  Rationale: This avoids asking for new plaintext secrets and keeps the migration self-contained while still allowing the nanobot resources to be removed later.
  Date/Author: 2026-04-22 / Codex
- Decision: Keep the deployment to Telegram only and do not add an ingress or service for the optional Hermes API/dashboard port.
  Rationale: The user asked for an allowlist-only Telegram bot and asked for the simplest Hermes-native deployment. Adding external exposure would expand the security surface without solving the requested use case.
  Date/Author: 2026-04-22 / Codex
- Decision: Use the official `nousresearch/hermes-agent` image and its native `hermes gateway` subcommand path instead of rebuilding Hermes or wrapping it in custom bootstrap scripts.
  Rationale: The user explicitly asked to keep this Hermes-native, and the official image already ships the bootstrap logic for `/opt/data`, config, and gateway startup.
  Date/Author: 2026-04-22 / Codex
- Decision: Enable the API server internally with `API_SERVER_ENABLED=true` and probe it locally with an exec check.
  Rationale: Hermes only exposes `/health` when the API server is enabled, and Kubernetes HTTP probes target the pod IP rather than loopback. The exec probe keeps the deployment self-contained and avoids needing an API auth key for an internal-only readiness check.
  Date/Author: 2026-04-22 / Codex
- Decision: Avoid nanobot-specific config maps, init containers, and custom note-sync logic.
  Rationale: Those were tied to nanobot’s Obsidian workflow and would impose an unrelated architecture on Hermes.
  Date/Author: 2026-04-22 / Codex
- Decision: Remove the nanobot manifests after Hermes is wired in, rather than keeping both deployments around.
  Rationale: Telegram bot tokens cannot safely be shared by two active pollers, and the user asked to remove nanobot completely afterwards.
  Date/Author: 2026-04-22 / Codex

## Outcomes & Retrospective

Hermes now replaces nanobot in the repo and in the cluster. The app manifests are native to Hermes, the bot token and allowlist are reused from the old deployment, the cluster overlay points at `apps/hermes-agent`, and Flux has already reconciled the new app so the Hermes pod is Ready. The old nanobot workload has been removed.

## Context and Orientation

The existing nanobot deployment used to live under `apps/nanobot/` and was wired into Flux through `clusters/home/overlays/apps/nanobot.yaml`, which was referenced from `clusters/home/overlays/kustomization.yaml`. That stack has now been removed and replaced by `apps/hermes-agent/` plus `clusters/home/overlays/apps/hermes-agent.yaml`.

Hermes is intentionally lighter than the old nanobot stack. It does not need the Obsidian sync config maps, the custom Python bootstrap layer, or any note-indexing sidecars. The official image already provides the gateway process and bootstraps its own writable home under `/opt/data`, so the deployment only needs the persistent volume, the secret-backed environment variables, and a health probe against `/health`.

The Telegram credentials are authorization secrets, not app configuration. In this repository, Telegram access is controlled by `TELEGRAM_BOT_TOKEN` and `TELEGRAM_ALLOWED_USERS`. Hermes reads them from the container environment, so the Deployment injects those variables directly from the Hermes SOPS Secret.

## Plan of Work

First, keep the Hermes app native and minimal. Add a `kustomization.yaml`, a `pvc.yaml`, a `deployment.yaml`, and a SOPS Secret file under `apps/hermes-agent/secrets/`. The Deployment should run `nousresearch/hermes-agent:latest`, mount the PVC at `/opt/data`, set `HERMES_HOME=/opt/data`, and launch the gateway through the Hermes CLI subcommand path (`hermes gateway`, expressed in Kubernetes as `args: ["gateway"]` because the image entrypoint already provides `hermes`). It should include readiness and liveness probes against `http://127.0.0.1:8642/health`.

Second, create the Hermes Secret by copying the encrypted values from `apps/nanobot/secrets/nanobot-secrets.sops.yaml` for the Telegram bot token, the Telegram allowlist, and the OpenRouter API key. The secret should be named `hermes-agent-secrets`, and the Deployment should reference that secret instead of the nanobot one.

Third, update `clusters/home/overlays/kustomization.yaml` so Flux reconciles Hermes instead of nanobot. Add a new `clusters/home/overlays/apps/hermes-agent.yaml` Flux `Kustomization` that points at `./apps/hermes-agent`, and remove the old nanobot Flux overlay file. If the old nanobot overlay is still referenced anywhere else, remove that reference too.

Fourth, delete the `apps/nanobot/` manifests after Hermes is in place. Keep the repo clean by removing the old nanobot Kustomization, Deployment, PVC, config maps, and secret file so the cluster has only one Telegram bot definition left.

Fifth, validate the result by rendering the new Hermes app with Kustomize and rendering the cluster overlay tree that includes it. If cluster access is available, reconcile Flux and confirm the Hermes pod becomes Ready and the nanobot workload disappears.

## Concrete Steps

Work from the repository root: `/Users/def4alt/source/homelab`.

1. Create the new app directory and copy the nanobot manifest skeleton into Hermes-specific files.
2. Edit the copied manifests so the app name, secret name, image, command, probes, and volume paths all match Hermes.
3. Copy the encrypted nanobot Telegram and OpenRouter secret values into the new Hermes SOPS secret file.
4. Add the new Flux overlay file for Hermes and update `clusters/home/overlays/kustomization.yaml` to reference it.
5. Remove the nanobot overlay reference and delete the nanobot app files.
6. Run:

       kustomize build apps/hermes-agent
       kustomize build clusters/home/overlays

   Expect both commands to complete without errors and to show the Hermes resources instead of nanobot.
7. If Flux is available in the cluster context, run the relevant reconcile command and watch for the Hermes pod to become Ready.

## Validation and Acceptance

The migration is complete when these are all true:

- `kustomize build apps/hermes-agent` succeeds.
- `kustomize build clusters/home/overlays` succeeds and includes the Hermes Flux Kustomization instead of the nanobot one.
- The cluster only has one active Telegram bot Deployment for this app role.
- The Hermes pod reports healthy through `/health` and receives Telegram messages only from the allowlisted Telegram user ID(s).
- The old `nanobot` app manifests are removed from the repository.

A human should also be able to confirm the bot by sending a Telegram message from an allowlisted account and seeing Hermes reply.

## Idempotence and Recovery

The file edits are safe to repeat because they are manifest-only changes. If a reconcile fails, restore the previous state with `git checkout -- .` or by reverting the commit, then re-run the Kustomize builds before reconciling again. If the Hermes rollout needs to be rolled back quickly, reintroduce the nanobot overlay and Deployment from git history only after making sure the Telegram token is not active in two places at once.

## Artifacts and Notes

The most important proof artifacts after implementation should be short and boring:

    $ kustomize build apps/hermes-agent | rg 'kind:|name:'
    kind: Deployment
    name: hermes-agent
    kind: PersistentVolumeClaim
    name: hermes-agent-data

    $ kustomize build clusters/home/overlays | rg 'hermes-agent|nanobot'
    hermes-agent
    # no nanobot resources remain

## Interfaces and Dependencies

The new Deployment should read these environment variables from `hermes-agent-secrets`:

    TELEGRAM_BOT_TOKEN
    TELEGRAM_ALLOWED_USERS
    OPENROUTER_API_KEY

It should also set `HERMES_HOME=/opt/data`, keep the image’s native startup path, and expose container port `8642` internally for the health probe only. No Ingress or Service is required for this migration.

Note: this plan intentionally removes nanobot after Hermes is live. That is the user-facing migration boundary, and the repo should end with one bot workload, not two.

---

Plan updated 2026-04-22 after confirming the user wants to reuse the nanobot credentials and remove nanobot completely once Hermes is deployed.
