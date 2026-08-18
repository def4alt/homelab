# Manage Nikitos Home Assistant access through GitOps

This ExecPlan is a living document and must be maintained in accordance with `.agent/PLANS.md`. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must remain current.

## Purpose / Big Picture

Nikitos can sign in to `https://home.def4alt.com` using the same username and password at both the Authentik access gate and Home Assistant login. The account and credential will survive application restoration because Flux can recreate them from SOPS-encrypted manifests in Git. SOPS encrypts sensitive YAML values before they are committed; Flux decrypts them only inside the cluster.

## Progress

- [x] (2026-08-18 11:23Z) Verified that active Authentik user `nikitos` exists and created the matching Home Assistant user live.
- [x] (2026-08-18 11:23Z) Verified the chosen credential against Home Assistant's authentication command.
- [x] (2026-08-18 11:27Z) Added SOPS-encrypted Authentik and Home Assistant account manifests.
- [x] (2026-08-18 11:27Z) Added idempotent account reconciliation to both application deployments.
- [x] (2026-08-18 11:29Z) Rendered and validated the Kustomize resources, Helm charts, encrypted-file status, and decrypted Secret schemas locally.
- [x] (2026-08-18 11:34Z) Committed and pushed revision `334ccc8`, reconciled Flux and both Helm releases, and proved both account credentials after successful rollouts.

## Surprises & Discoveries

- Observation: Home Assistant has no supported YAML user resource, but its container provides an official idempotent-capable authentication CLI.
  Evidence: `python -m homeassistant --script auth -c /config --help` lists `list`, `add`, `validate`, and `change_password`.
- Observation: The Home Assistant Helm chart supports arbitrary init containers, but they must explicitly mount the existing configuration volume.
  Evidence: chart version `0.3.74` renders `.Values.initContainers` directly and names the deployment volume `home-assistant-pvc`.
- Observation: Authentik's chart can mount blueprint definitions from Kubernetes Secrets, keeping the blueprint password encrypted in Git.
  Evidence: Authentik chart version `2026.5.6` exposes `blueprints.secrets`.
- Observation: This repository's Home Assistant Kustomization references a shared Secret above its directory, so the default Kustomize load restriction rejects the build.
  Evidence: `kubectl kustomize apps/home-assistant --load-restrictor=LoadRestrictionsNone` succeeds and client-side Kubernetes schema validation then passes.

## Decision Log

- Decision: Use an encrypted Authentik blueprint and a Home Assistant init container instead of committing generated runtime storage files.
  Rationale: Runtime storage contains unrelated mutable state. The selected mechanisms are scoped to this user, declarative, repeatable, and keep plaintext credentials out of Git.
  Date/Author: 2026-08-18 / Codex
- Decision: Reconcile the configured password on each Authentik blueprint application and each Home Assistant pod start.
  Rationale: This makes restore behavior deterministic. Future password changes must update both encrypted manifests.
  Date/Author: 2026-08-18 / Codex

## Outcomes & Retrospective

Nikitos access is managed end to end through GitOps. Flux applied revision `334ccc8`; Authentik and Home Assistant rolled out successfully. The same encrypted credential validates in both systems, Authentik contains exactly one active non-admin `nikitos` user, and the Home Assistant init container idempotently changed the existing account password before the main application started. No plaintext credential is stored in Git.

## Context and Orientation

Flux applies `apps/authentik` and `apps/home-assistant` to their matching namespaces. `apps/authentik/helmrelease.yaml` mounts Git-managed Authentik blueprints. `apps/home-assistant/helmrelease.yaml` deploys Home Assistant and mounts the persistent `/config` directory where its authentication storage lives. Files below each application's `secrets/` directory match `.sops.yaml` and must contain encrypted `data` or `stringData` values before commit.

Public Home Assistant requests first pass through the Authentik forward-auth middleware configured in `apps/home-assistant/helmrelease.yaml`; after that gate, Home Assistant presents its own login. Therefore `nikitos` needs an account in both systems.

## Plan of Work

Create `apps/authentik/secrets/nikitos-blueprint.sops.yaml` as a Secret whose `blueprint.yaml` defines an active non-admin `authentik_core.user` named `nikitos` with the chosen password. Add that Secret to `apps/authentik/kustomization.yaml` and to `blueprints.secrets` in `apps/authentik/helmrelease.yaml`.

Create `apps/home-assistant/secrets/nikitos-account.sops.yaml` containing the username and password. Add it to `apps/home-assistant/kustomization.yaml`. Extend `apps/home-assistant/helmrelease.yaml` with an init container using the same Home Assistant image. It mounts `home-assistant-pvc` at `/config`, reads the encrypted Secret through environment variables, creates the user when absent, and otherwise sets the declared password.

Render both Kustomizations, confirm SOPS reports encrypted files, commit and push. Reconcile both Flux Kustomizations. Verify pod readiness, Authentik's account state, and Home Assistant credential validation without printing the password.

## Concrete Steps

Run from `/Users/def4alt/src/github.com/def4alt/homelab`:

    sops --encrypt --in-place apps/authentik/secrets/nikitos-blueprint.sops.yaml
    sops --encrypt --in-place apps/home-assistant/secrets/nikitos-account.sops.yaml
    kubectl kustomize apps/authentik >/tmp/authentik.yaml
    kubectl kustomize apps/home-assistant >/tmp/home-assistant.yaml
    sops filestatus apps/authentik/secrets/nikitos-blueprint.sops.yaml
    sops filestatus apps/home-assistant/secrets/nikitos-account.sops.yaml

After commit and push:

    flux reconcile kustomization authentik --with-source
    flux reconcile kustomization home-assistant --with-source
    kubectl -n home-assistant rollout status deploy/home-assistant --timeout=10m

## Validation and Acceptance

Both `kubectl kustomize` commands must exit successfully. `sops filestatus` must report encrypted files, and repository searches must not find the plaintext password outside this plan's runtime context (the plan does not record it). The Authentik user query must report username `nikitos`, active status true, and no admin privileges. Home Assistant's `auth list` must include `nikitos`, while `auth validate` using the password sourced directly from the Kubernetes Secret must print `Auth valid`. Both application workloads must be Ready after reconciliation.

## Idempotence and Recovery

Blueprint reconciliation and the Home Assistant init script are safe to repeat. Existing accounts are updated instead of duplicated. If the Home Assistant init command fails, the main container remains stopped, protecting against silently starting without the declared user; inspect init-container logs, correct the encrypted manifest, push, and let Flux retry. Rollback consists of reverting the commit, but removing the manifests does not delete existing runtime users automatically, preventing accidental lockout.

## Artifacts and Notes

Initial live validation produced:

    Authentik password updated for nikitos
    Home Assistant user created: nikitos
    Auth valid

Post-Flux validation produced:

    Applied revision: main@sha1:334ccc8b
    deployment "authentik-server" successfully rolled out
    deployment "authentik-worker" successfully rolled out
    deployment "home-assistant" successfully rolled out
    {'count': 1, 'username': 'nikitos', 'active': True, 'staff': False, 'superuser': False, 'password_valid': True}
    Auth valid
    Password changed

## Interfaces and Dependencies

Authentik consumes a blueprint Secret listed under `spec.values.blueprints.secrets`. The blueprint uses model `authentik_core.user`, identifier `username: nikitos`, and ordinary non-superuser attributes. Home Assistant uses `python -m homeassistant --script auth -c /config` from image `ghcr.io/home-assistant/home-assistant:2026.8.1`; the init container receives `NIKITOS_USERNAME` and `NIKITOS_PASSWORD` from a namespace-local Secret and mounts volume `home-assistant-pvc` at `/config`.

Change note: Initial plan created after live access was established and the user explicitly requested GitOps management.

Change note (2026-08-18 11:29Z): Recorded completed implementation and local validation, including the existing Kustomize load-restriction requirement.

Change note (2026-08-18 11:34Z): Recorded the pushed revision, successful Flux and Helm reconciliations, and post-rollout credential evidence; marked the plan complete.
