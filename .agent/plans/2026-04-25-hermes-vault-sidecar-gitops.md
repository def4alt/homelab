# Hermes Vault Sidecar GitOps Implementation Plan

> **For implementation:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Replace the current SOPS-backed Kubernetes Secret injection for `apps/hermes-agent` with Vault Community Edition + Vault Agent Injector, so Hermes receives secrets from a memory-backed file mount instead of from Kubernetes Secret env vars.

**Architecture:** Deploy Vault Community in a dedicated `vault` namespace via Flux using the official Helm chart, with integrated Raft storage on a Longhorn-backed PVC and the built-in injector webhook enabled. Update the Hermes Deployment in the `ai` namespace to authenticate to Vault with a dedicated Kubernetes service account, receive templated secret files on a tmpfs mount, and stop referencing `hermes-agent-secrets`. Keep Vault bootstrap, init, and unseal as an explicit out-of-band runbook step because the root token and unseal material must not be committed to Git or stored in-cluster. Runtime redaction is treated as a separate phase unless Hermes already exposes a supported hook for pre-context output filtering.

**Tech Stack:** Flux `Kustomization`, Kustomize, HelmRelease, HashiCorp Vault Helm chart, Vault Agent Injector, Vault Kubernetes auth, Longhorn PVC, Kubernetes NetworkPolicy, SOPS only for non-secret repo-managed manifests.

---

## Purpose / Big Picture

Today the repo deploys Hermes from `apps/hermes-agent/` and injects `OPENROUTER_API_KEY`, `TELEGRAM_BOT_TOKEN`, and `TELEGRAM_ALLOWED_USERS` through the SOPS-encrypted Kubernetes Secret `hermes-agent-secrets`. That works, but the decrypted secret values still land in Kubernetes Secret objects in etcd and are exposed to the Hermes process through environment variables.

The target state replaces that pattern with Vault-backed delivery. Vault runs in its own namespace, persists its encrypted Raft data on a PVC, and exposes the injector webhook. Hermes authenticates to Vault using a Kubernetes service account token, and Vault Agent renders secret material into an in-memory filesystem inside the pod. Hermes reads from that mount at startup. The repo should end with no app-facing Kubernetes Secret for Hermes credentials and no `secretKeyRef` usage in the Hermes Deployment.

One correction to the original goal needs to be explicit in the plan: Hermes cannot use a secret without that secret existing in plaintext in Hermes process memory at the moment it is consumed. The implementation can keep secrets out of etcd, out of pod spec env vars, and off persistent disk, but it cannot guarantee “never in agent memory as plaintext.” The realistic goal is to minimize lifetime and propagation, not to eliminate in-process plaintext entirely.

## Recommended Approach and Alternatives

### Recommended: Official Vault Helm chart with integrated injector

Use a new `apps/vault/` app that installs the official HashiCorp `vault` Helm chart with a single Vault server replica, integrated Raft storage, and `injector.enabled=true`. This keeps the repo aligned with existing infra patterns like `apps/cert-manager/` and `apps/longhorn/`, where Flux manages a Helm repository plus a Helm release. The same app directory can also carry namespace-local network policies and any supporting RBAC that the chart does not already create.

This is the best fit for the repo because it is small, GitOps-friendly, and keeps Vault and its injector in one logical place. It also allows a clean Flux dependency chain: `namespaces` → `vault` → `hermes-agent`.

### Alternative 1: Raw YAML for Vault + injector

Possible, but not worth it here. Vault has enough moving parts that hand-maintaining Deployments, webhook configuration, RBAC, services, and storage objects would create unnecessary drift risk.

### Alternative 2: Keep SOPS + Kubernetes Secrets

Operationally simpler, but it does not satisfy the stated design goal of keeping Hermes credentials out of etcd and out of env vars.

## Constraints and Assumptions

- This is a single-node k3s lab. Availability is less important than simplicity and recoverability.
- Vault Community Edition likely means manual unseal after node reboot unless an external auto-unseal mechanism already exists outside this repo.
- The repo is GitOps-first, but Vault initialization, unseal key custody, and root-token handling cannot be fully GitOps-managed without reintroducing high-value secrets into etcd or Git.
- The current Hermes deployment has `automountServiceAccountToken: false`; Vault Kubernetes auth will require a dedicated service account token to be present or projected.
- Runtime redaction is not a pure manifest change. It requires confirmed Hermes support or a custom wrapper/image. Treat it as a separate phase unless implementation discovery proves a native hook exists.
- NetworkPolicies must be introduced carefully because the injector is part of the admission path. A policy mistake can block new pod creation.

## Repo Context

Current relevant files:

- `apps/hermes-agent/deployment.yaml`
- `apps/hermes-agent/kustomization.yaml`
- `apps/hermes-agent/pvc.yaml`
- `apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml`
- `apps/namespaces/kustomization.yaml`
- `apps/namespaces/namespace-ai.yaml`
- `clusters/home/overlays/kustomization.yaml`
- `clusters/home/overlays/apps/hermes-agent.yaml`

There is no existing Vault app, no `vault` namespace manifest, and no existing NetworkPolicy pattern in the app directories beyond what Flux ships for itself.

## Files to Create / Modify

### Create

- `apps/vault/kustomization.yaml`
- `apps/vault/helmrepository.yaml`
- `apps/vault/helmrelease.yaml`
- `apps/vault/networkpolicy-vault.yaml`
- `apps/vault/networkpolicy-injector.yaml` (only if needed after validation; may be staged later)
- `apps/vault/rbac-auth-delegator.yaml` (only if the chart values do not already cover Kubernetes auth token review)
- `apps/namespaces/namespace-vault.yaml`
- `clusters/home/overlays/infra/vault.yaml`
- `apps/hermes-agent/serviceaccount.yaml`
- `apps/hermes-agent/configmap-launcher.yaml` or `apps/hermes-agent/start-hermes.sh` packaged via ConfigMap
- `apps/hermes-agent/networkpolicy.yaml`
- `docs/operations/vault-bootstrap-hermes.md` or `.agent/plans/2026-04-25-vault-bootstrap-runbook.md` for manual init/unseal/auth configuration steps

### Modify

- `apps/namespaces/kustomization.yaml`
- `clusters/home/overlays/kustomization.yaml`
- `apps/hermes-agent/kustomization.yaml`
- `apps/hermes-agent/deployment.yaml`
- `clusters/home/overlays/apps/hermes-agent.yaml`

### Delete after cutover

- `apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml`

## Decision Log

- Decision: Treat Vault as infrastructure, but still place it under `apps/vault/` to match the repo’s current pattern of app directories reconciled by Flux overlay entries.
  Rationale: The repo already uses app directories for both end-user apps and infra components. This keeps the change consistent.
  Date/Author: 2026-04-25 / Codex

- Decision: Use the official Vault Helm chart instead of bespoke manifests.
  Rationale: It already wires the injector, services, webhook, and server components and is easier to maintain in Flux.
  Date/Author: 2026-04-25 / Codex

- Decision: Keep Vault bootstrap and unseal out of GitOps.
  Rationale: A GitOps-managed root token or unseal secret would undermine the entire security objective.
  Date/Author: 2026-04-25 / Codex

- Decision: Defer runtime redaction to a second phase unless Hermes exposes a documented hook for pre-context output filtering.
  Rationale: That behavior is application-level, not infrastructure-level, and should not block the more concrete secret-delivery migration.
  Date/Author: 2026-04-25 / Codex

- Decision: Stage NetworkPolicies conservatively.
  Rationale: The injector is admission-path infrastructure; overly strict policies can break unrelated pod scheduling.
  Date/Author: 2026-04-25 / Codex

## Implementation Phases

### Phase 1: Install Vault infrastructure via Flux

**Objective:** Get Vault CE and the injector into the cluster in a dedicated namespace, without yet changing Hermes.

**Work items:**

1. Add `apps/namespaces/namespace-vault.yaml` with `metadata.name: vault`.
2. Add `namespace-vault.yaml` to `apps/namespaces/kustomization.yaml`.
3. Create `apps/vault/helmrepository.yaml` pointing at the official HashiCorp chart repository.
4. Create `apps/vault/helmrelease.yaml` using conservative single-node values:
   - `injector.enabled: true`
   - single server replica
   - integrated Raft storage enabled
   - Longhorn-backed persistent storage
   - conservative CPU/memory requests and limits
   - UI disabled unless explicitly wanted
   - auth delegator support enabled if exposed by chart values
5. Create `apps/vault/kustomization.yaml` referencing the Helm repo/release and any supporting manifests.
6. Create `clusters/home/overlays/infra/vault.yaml` as a Flux `Kustomization` with `dependsOn: [namespaces, longhorn]`.
7. Add `infra/vault.yaml` to `clusters/home/overlays/kustomization.yaml` before `apps/hermes-agent.yaml`.
8. Render validation:
   - `kubectl kustomize apps/vault`
   - `kubectl kustomize clusters/home/overlays`

**Notes:**
- Do not attempt to configure Vault auth or write secrets yet.
- Do not add restrictive NetworkPolicies until the chart is confirmed healthy.

### Phase 2: Bootstrap Vault out of band

**Objective:** Initialize Vault safely without storing bootstrap material in Git or in-cluster Secrets.

**Work items:**

1. Write a short operator runbook describing:
   - how to port-forward or access the in-cluster Vault service
   - how to run `vault operator init`
   - where to store unseal keys and initial root token outside the repo
   - how to unseal the server
2. Enable and configure Kubernetes auth in Vault.
3. Create or verify a KV v2 secrets engine path for app secrets, for example `kv/`.
4. Write the Hermes credentials into Vault from an operator workstation, using the existing SOPS secret values only as migration input.
5. Create a least-privilege policy that allows Hermes read access only to its path, for example `kv/data/hermes-agent`.
6. Create a Vault Kubernetes auth role bound only to:
   - service account: `hermes-agent`
   - namespace: `ai`
7. Record the exact CLI commands in the runbook, but do not commit any resulting root token, unseal key, or exported plaintext secret values.

**Important:**
- This phase is intentionally not fully automated by Flux.
- If full unattended reboot recovery is a hard requirement, revisit the Vault CE choice or add an external unseal solution before implementation.

### Phase 3: Prepare Hermes for Vault-authenticated injection

**Objective:** Add the Kubernetes identity and pod wiring Hermes needs before removing the existing secret.

**Work items:**

1. Create `apps/hermes-agent/serviceaccount.yaml` for a dedicated `hermes-agent` service account in namespace `ai`.
2. Add that service account to `apps/hermes-agent/kustomization.yaml`.
3. Update `apps/hermes-agent/deployment.yaml`:
   - set `serviceAccountName: hermes-agent`
   - remove `automountServiceAccountToken: false` if using the default projected token
   - keep the existing pod/container hardening where compatible
4. Decide how Hermes reads Vault-rendered files:
   - preferred: Hermes natively reads file-based config or a rendered `.env` file without exporting process env vars
   - fallback: use a tiny launcher script from ConfigMap that reads files from `/run/vault` and starts Hermes
5. Add a ConfigMap-delivered launcher only if required by Hermes runtime behavior.
6. Keep the existing SOPS secret and `secretKeyRef` env vars in place until Vault injection is verified.

**Discovery checkpoint:**
- Confirm from Hermes docs or a container test whether Hermes can consume file-based secrets directly.
- If Hermes only supports env vars, decide whether that is acceptable or whether this blocks the migration objective.

### Phase 4: Switch Hermes from Kubernetes Secrets to Vault injection

**Objective:** Cut Hermes over from `secretKeyRef` env vars to Vault Agent file injection.

**Work items:**

1. Add Vault injector annotations to the Hermes pod template metadata, for example:
   - enable injection
   - set the Vault role name
   - set secret path annotations
   - add template annotations to render either:
     - individual secret files under `/run/vault/`, or
     - a single Hermes-specific config/env file under a tmpfs mount
2. Add a memory-backed volume for the secret mount if the injector configuration requires an explicit target volume.
3. Remove the `secretKeyRef` env vars for:
   - `OPENROUTER_API_KEY`
   - `TELEGRAM_BOT_TOKEN`
   - `TELEGRAM_ALLOWED_USERS`
4. If using a launcher script, update container `command` / `args` to use it.
5. Keep the current PVC and existing health probes unless Hermes startup behavior changes.
6. Render validation:
   - `kubectl kustomize apps/hermes-agent`
   - `kubectl kustomize clusters/home/overlays`
7. After successful cluster validation, delete `apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml` and remove it from `apps/hermes-agent/kustomization.yaml`.

**Cutover criteria:**
- Hermes pod gets an injected Vault sidecar or init+sidecar as intended.
- `env` inside the Hermes container no longer shows those three app secrets.
- Hermes still authenticates to Telegram and OpenRouter successfully.

### Phase 5: Add and tighten NetworkPolicies

**Objective:** Restrict Vault reachability without breaking the injector or Vault auth flows.

**Work items:**

1. Add a Hermes namespace policy in `apps/hermes-agent/networkpolicy.yaml` that allows egress only to:
   - Vault service in namespace `vault`
   - DNS
   - any existing destinations Hermes already requires for normal operation, such as Telegram/OpenRouter egress, if you are using egress-deny semantics
2. Add a Vault namespace policy in `apps/vault/networkpolicy-vault.yaml` that allows ingress only from:
   - Hermes pods in namespace `ai`
   - Vault injector or Vault pods in namespace `vault` as required
3. Explicitly allow DNS and Kubernetes API egress for Vault if required for Kubernetes auth token review.
4. Delay webhook-facing restrictions until validation proves they do not block admission.
5. Validate from a throwaway pod that unauthorized namespaces cannot reach the Vault service.

**Staging recommendation:**
- First apply policies that protect the Vault server service.
- Only later restrict injector webhook traffic if cluster testing shows a safe rule set.

### Phase 6: Optional runtime redaction phase

**Objective:** Add the “last-line defense” only if Hermes or a wrapper can do it correctly.

**Work items:**

1. Confirm whether Hermes exposes a documented hook, middleware layer, or tool-output interceptor before LLM context assembly.
2. If yes, implement redaction in Hermes config or a thin wrapper.
3. If no, record that this requirement cannot be satisfied purely through Kubernetes manifests and should be tracked as a separate application customization effort.
4. Do not claim completion of this phase based on log shipping or sidecar log masking alone; the requirement is pre-context redaction, not just log redaction.

## Concrete File-Level Plan

### Task 1: Add the `vault` namespace

**Files:**
- Create: `apps/namespaces/namespace-vault.yaml`
- Modify: `apps/namespaces/kustomization.yaml`

**Expected outcome:**
Flux creates a dedicated `vault` namespace before the Vault app reconciles.

### Task 2: Add the Vault app scaffolding

**Files:**
- Create: `apps/vault/kustomization.yaml`
- Create: `apps/vault/helmrepository.yaml`
- Create: `apps/vault/helmrelease.yaml`

**Expected outcome:**
The repo can render a minimal single-node Vault CE deployment with injector enabled.

### Task 3: Wire Vault into Flux overlays

**Files:**
- Create: `clusters/home/overlays/infra/vault.yaml`
- Modify: `clusters/home/overlays/kustomization.yaml`

**Expected outcome:**
Flux reconciles Vault after namespaces and Longhorn, before Hermes depends on it.

### Task 4: Add Hermes Kubernetes identity

**Files:**
- Create: `apps/hermes-agent/serviceaccount.yaml`
- Modify: `apps/hermes-agent/kustomization.yaml`
- Modify: `apps/hermes-agent/deployment.yaml`

**Expected outcome:**
Hermes has a dedicated service account that Vault Kubernetes auth can bind to.

### Task 5: Add Vault bootstrap runbook

**Files:**
- Create: `docs/operations/vault-bootstrap-hermes.md` or `.agent/plans/2026-04-25-vault-bootstrap-runbook.md`

**Expected outcome:**
An operator can initialize, unseal, enable Kubernetes auth, write secrets, and create the Hermes policy/role without guessing.

### Task 6: Add Hermes injector annotations and file-based secret consumption

**Files:**
- Modify: `apps/hermes-agent/deployment.yaml`
- Create: `apps/hermes-agent/configmap-launcher.yaml` only if required
- Modify: `apps/hermes-agent/kustomization.yaml`

**Expected outcome:**
Hermes consumes Vault-rendered secrets from a memory-backed filesystem and no longer references `secretKeyRef` env vars.

### Task 7: Remove the old Hermes Kubernetes Secret

**Files:**
- Delete: `apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml`
- Modify: `apps/hermes-agent/kustomization.yaml`

**Expected outcome:**
The final repo no longer manages a Kubernetes Secret containing Hermes runtime credentials.

### Task 8: Add and validate NetworkPolicies

**Files:**
- Create: `apps/vault/networkpolicy-vault.yaml`
- Create: `apps/hermes-agent/networkpolicy.yaml`
- Optionally create later: `apps/vault/networkpolicy-injector.yaml`

**Expected outcome:**
Vault is reachable only by the intended workloads and required control-plane paths.

## Validation and Acceptance

### Render-time validation

Run from repo root:

```bash
kubectl kustomize apps/vault
kubectl kustomize apps/hermes-agent
kubectl kustomize clusters/home/overlays
```

Expect:
- all commands succeed
- rendered output includes the new `vault` namespace and Flux Kustomization
- rendered Hermes Deployment no longer contains `secretKeyRef` entries in the final cutover state

### Cluster validation

If cluster access is available:

```bash
flux reconcile kustomization namespaces --with-source
flux reconcile kustomization vault --with-source
flux reconcile kustomization hermes-agent --with-source
kubectl -n vault get pods
kubectl -n ai get pods
kubectl -n ai describe pod deploy/hermes-agent
```

Expect:
- Vault server is Running after init/unseal
- injector webhook is Running
- Hermes pod shows Vault injection annotations and injected containers/volumes

### Security validation

Inside the Hermes container:

```bash
kubectl -n ai exec deploy/hermes-agent -c hermes -- /bin/sh -lc 'env | rg "OPENROUTER|TELEGRAM" || true'
```

Expect:
- no matching env vars in the final state

Check mounted secrets location:

```bash
kubectl -n ai exec deploy/hermes-agent -c hermes -- /bin/sh -lc 'ls -la /run/vault || ls -la /vault/secrets'
```

Expect:
- secret files exist only in the injected memory-backed location

Check that the old Kubernetes Secret is gone:

```bash
kubectl -n ai get secret hermes-agent-secrets
```

Expect:
- `NotFound`

### Functional validation

- Hermes still responds in Telegram for allowlisted users.
- Hermes can still authenticate to OpenRouter.
- Restarting the Hermes pod still results in successful Vault auth and reinjection.

## Risks and Mitigations

- **Risk:** Vault stays sealed after node reboot.
  **Mitigation:** Accept manual unseal as part of homelab operations, or defer implementation until an external unseal strategy exists.

- **Risk:** Hermes does not support file-native secret reads.
  **Mitigation:** Add an explicit discovery checkpoint before deleting the existing SOPS secret path. Do not claim the “no env vars” goal if the implementation requires exporting env vars at runtime.

- **Discovery:** Hermes gateway hot-reloads `HERMES_HOME/.env` directly, which means a Vault-rendered secret file can be consumed without process env vars, but writing that file straight into `/opt/data/.env` would persist secrets on the PVC. The cutover should therefore use a tmpfs-rendered Vault file plus a symlink at `/opt/data/.env` rather than writing secret contents onto the Hermes data volume.

- **Risk:** NetworkPolicy breaks the injector webhook or Vault auth.
  **Mitigation:** Stage policy rollout after core functionality works, and validate with throwaway pods before tightening.

- **Risk:** Flux ordering race between Vault and Hermes.
  **Mitigation:** Add `dependsOn` in `clusters/home/overlays/apps/hermes-agent.yaml` so Hermes reconciles only after `vault` is present.

- **Risk:** Bootstrap secrets leak during migration from the old SOPS secret.
  **Mitigation:** Perform migration from an operator workstation, do not write plaintext to repo files, and remove the old Kubernetes Secret manifest immediately after cutover.

## Suggested `dependsOn` Update for Hermes

Update `clusters/home/overlays/apps/hermes-agent.yaml` to depend on at least:

- `namespaces`
- `vault`
- `longhorn`

This ensures the namespace exists, Vault is reconciled, and the Hermes PVC storage class is available before Hermes rolls.

## Expected End State

After the plan is implemented and validated:

- `vault` exists as a dedicated namespace managed by Flux.
- Vault CE runs from a Longhorn-backed Raft volume and is reachable only where required.
- Hermes uses a dedicated service account and Vault Agent injection.
- Hermes no longer references `hermes-agent-secrets` or any app secret via `secretKeyRef` env vars.
- The repo no longer contains the Hermes runtime credentials as a Kubernetes Secret manifest.
- Runtime redaction is either implemented as a separate verified phase or explicitly tracked as not yet delivered.

## Progress

- [x] (2026-04-25) Reviewed the current Hermes deployment and Flux overlay structure.
- [x] (2026-04-25) Confirmed there is no existing Vault app or `vault` namespace in the repo.
- [x] (2026-04-25) Identified the current blockers: Vault bootstrap is not fully GitOps-safe, Hermes file-based secret support is unverified, and runtime redaction is application-level.
- [x] (2026-04-25) Add namespace and Flux wiring for Vault.
- [x] (2026-04-25) Add Vault HelmRelease and baseline values.
- [x] (2026-04-25) Render validation passed for `apps/vault` and `clusters/home/overlays` after wiring the new Vault Flux Kustomization.
- [x] (2026-04-25) Commit `feat(vault): add Flux-managed Vault bootstrap` and push it to `origin/main` so Flux can reconcile the new Vault app.
- [x] (2026-04-25) Reconcile Flux `source/git`, `kustomization/namespaces`, and `kustomization/vault`; the injector is Running and `vault-0` is Running but not Ready yet because Vault is not initialized/unsealed.
- [x] (2026-04-25) Write the bootstrap runbook for init/unseal/Kubernetes auth/policy creation at `docs/operations/vault-bootstrap-hermes.md`.
- [x] (2026-04-25) Add the Hermes service account and Flux `dependsOn` wiring so the app can later bind Vault Kubernetes auth without racing namespace, storage, or Vault reconciliation.
- [x] (2026-04-25) Prepare Hermes injector annotations and a launcher ConfigMap that waits for a Vault-rendered `.env`, then symlinks `/opt/data/.env` to the injected file so secrets stay off the PVC.
- [x] (2026-04-25) Remove `secretKeyRef` usage from the staged Hermes Deployment manifest, but do not apply the cutover until Vault is initialized, unsealed, and populated with Hermes secrets.
- [x] (2026-04-25) Remove the Hermes SOPS secret manifest after the Vault-injected Hermes rollout succeeded and verification confirmed the pod no longer exposed app secrets via env vars.
- [ ] Add and validate NetworkPolicies.
- [x] (2026-04-25) Validate the Vault-backed Hermes rollout in cluster: the pod injected `vault-agent-init` and `vault-agent`, `/opt/data/.env` resolved to `/vault/secrets/hermes.env`, and `env` no longer exposed `OPENROUTER_*` or `TELEGRAM_*` variables.
- [x] (2026-04-25) Extend the Vault-rendered Hermes `.env` template to include `GITHUB_TOKEN` sourced from `kv/hermes-agent.github_token`.

## Notes for the Implementer

- Keep the implementation minimal. Do not add a Vault UI ingress, external exposure, or extra controllers unless there is a clear need.
- Prefer the smallest working Helm values file and only add custom RBAC/policies when the chart cannot express the requirement.
- Do not store Vault root tokens, unseal keys, or copied Hermes secrets in any committed file.
- If implementation proves that Hermes can only consume secrets through env vars, stop and document that mismatch before deleting the current secret path.
