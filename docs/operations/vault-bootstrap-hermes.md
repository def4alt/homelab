# Vault Bootstrap Runbook for Hermes

This runbook covers the **manual, out-of-band** bootstrap steps for the Vault deployment added in this repo.

Use it after Flux has reconciled the `vault` app and before switching Hermes from Kubernetes `Secret` env vars to Vault Agent injection.

## Scope

This runbook covers:

- initializing Vault
- unsealing Vault
- enabling Kubernetes auth
- enabling a KV v2 secrets engine for app secrets
- writing Hermes secrets into Vault
- creating the Hermes read policy
- creating the Hermes Kubernetes auth role
- verifying that the Vault side is ready for Hermes integration

This runbook does **not** cover:

- automatic unseal
- external exposure for Vault
- Hermes deployment changes
- runtime redaction inside Hermes

## Prerequisites

- Flux has already reconciled the `vault` Kustomization.
- `vault-0` is running in the `vault` namespace.
- `vault-agent-injector` is running in the `vault` namespace.
- You have `kubectl` access to the cluster.
- You have a secure place **outside Git and outside the cluster** to store:
  - the unseal key(s)
  - the initial root token
- You still have access to the current Hermes secret values from the existing SOPS file:
  - `apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml`

## Current in-cluster resource names

These names are expected from the current manifests:

- namespace: `vault`
- Vault pod: `vault-0`
- Vault service: `vault`
- Vault active service: `vault-active`
- injector service: `vault-agent-injector-svc`
- Vault service account: `vault`

## 1. Confirm Vault is waiting for initialization

```bash
kubectl -n vault get pods
kubectl -n vault logs vault-0 --tail=20
```

Expected log lines before initialization:

- `security barrier not initialized`
- `seal configuration missing, not initialized`

## 2. Initialize Vault

Run the init command **once**.

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator init -key-shares=1 -key-threshold=1'
```

Important:

- Copy the output immediately into your password manager or other secure offline store.
- Do **not** save the output into this repo.
- Do **not** paste the output into chat logs, notes committed to Git, or Kubernetes Secrets.

The command returns at least:

- `Unseal Key 1`
- `Initial Root Token`

If Vault was already initialized, the command will fail with an "already initialized" message. In that case, continue to the next step.

## 3. Unseal Vault

Use the unseal key from the previous step.

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY>'
```

Verify status:

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault status'
```

Expected:

- `Initialized     true`
- `Sealed          false`

## 4. Log into Vault inside the pod

Open a shell in the Vault pod:

```bash
kubectl -n vault exec -it vault-0 -- sh
```

Inside the shell, set the Vault address and log in:

```bash
export VAULT_ADDR=http://127.0.0.1:8200
vault login <INITIAL_ROOT_TOKEN>
```

All remaining Vault CLI commands in this runbook assume you are still inside that shell.

## 5. Verify the server can review Kubernetes service account tokens

The Helm chart should already create the required `system:auth-delegator` binding for the Vault server service account.

From another terminal, you can confirm it with:

```bash
kubectl get clusterrolebinding vault-server-binding
```

Inside the Vault pod shell, confirm the projected token and CA files exist:

```bash
ls -l /var/run/secrets/kubernetes.io/serviceaccount/
```

Expected files include:

- `token`
- `ca.crt`
- `namespace`

## 6. Enable Kubernetes auth

Check whether it is already enabled:

```bash
vault auth list
```

If `kubernetes/` is missing, enable it:

```bash
vault auth enable kubernetes
```

Configure the auth method using the in-cluster service account token reviewer credentials:

```bash
vault write auth/kubernetes/config \
  kubernetes_host="https://${KUBERNETES_SERVICE_HOST}:${KUBERNETES_SERVICE_PORT_HTTPS}" \
  token_reviewer_jwt="$(cat /var/run/secrets/kubernetes.io/serviceaccount/token)" \
  kubernetes_ca_cert=@/var/run/secrets/kubernetes.io/serviceaccount/ca.crt
```

Verify:

```bash
vault read auth/kubernetes/config
```

## 7. Enable a KV v2 secrets engine at `kv/`

Check current mounts:

```bash
vault secrets list
```

If `kv/` is not present, enable it:

```bash
vault secrets enable -path=kv kv-v2
```

Verify:

```bash
vault secrets list | grep '^kv/'
```

## 8. Read the current Hermes secret values from SOPS

Run this on your workstation, **outside** the Vault pod shell:

```bash
sops -d apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml
```

Extract these values:

- `openrouter-api-key`
- `telegram-bot-token`
- `telegram-allowed-users`

Do not save the decrypted output into a file inside the repo.

## 9. Write Hermes secrets into Vault

Back in the Vault pod shell, write the Hermes secret values to `kv/hermes-agent`:

```bash
vault kv put kv/hermes-agent \
  openrouter_api_key='<OPENROUTER_API_KEY>' \
  telegram_bot_token='<TELEGRAM_BOT_TOKEN>' \
  telegram_allowed_users='<TELEGRAM_ALLOWED_USERS>'
```

Verify:

```bash
vault kv get kv/hermes-agent
```

## 10. Create the Hermes read policy

Write the policy:

```bash
cat <<'EOF' > /tmp/hermes-agent-policy.hcl
path "kv/data/hermes-agent" {
  capabilities = ["read"]
}
EOF
vault policy write hermes-agent /tmp/hermes-agent-policy.hcl
rm -f /tmp/hermes-agent-policy.hcl
```

Verify:

```bash
vault policy read hermes-agent
```

Expected policy:

```hcl
path "kv/data/hermes-agent" {
  capabilities = ["read"]
}
```

## 11. Create the Hermes Kubernetes auth role

This role is intended for the future Hermes service account:

- service account name: `hermes-agent`
- namespace: `ai`

Create the role:

```bash
vault write auth/kubernetes/role/hermes-agent \
  bound_service_account_names=hermes-agent \
  bound_service_account_namespaces=ai \
  policies=hermes-agent \
  ttl=24h
```

Verify:

```bash
vault read auth/kubernetes/role/hermes-agent
```

## 12. Optional: verify the auth role after the Hermes service account exists

After the repo adds and applies the `hermes-agent` service account in namespace `ai`, you can test Vault login from a short-lived token.

On your workstation:

```bash
kubectl -n ai create token hermes-agent
```

Inside the Vault pod shell, test login with the returned JWT:

```bash
vault write auth/kubernetes/login role=hermes-agent jwt='<JWT_FROM_KUBECTL_CREATE_TOKEN>'
```

Expected:

- a client token is returned
- attached policies include `hermes-agent`

## 13. Exit criteria before Hermes cutover

Do not remove the existing Kubernetes `Secret` flow for Hermes until all of these are true:

- `vault status` shows initialized and unsealed
- `vault auth list` includes `kubernetes/`
- `vault secrets list` includes `kv/`
- `vault kv get kv/hermes-agent` returns the expected keys
- `vault policy read hermes-agent` succeeds
- `vault read auth/kubernetes/role/hermes-agent` succeeds
- the future `hermes-agent` service account in namespace `ai` can authenticate successfully

## Recovery notes

### Vault pod restarts

If the pod restarts on this single-node setup, Vault may come back sealed.

Check:

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault status'
```

If sealed, unseal again:

```bash
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault operator unseal <UNSEAL_KEY>'
```

### Lost unseal key or root token

If you lose the unseal key or initial root token and have no recovery path, treat the Vault instance as unrecoverable and rebuild it from scratch. That is why the bootstrap output must be stored outside the repo in a durable secret store.

## Minimal verification summary

From your workstation:

```bash
kubectl -n vault get pods
kubectl -n vault exec -it vault-0 -- sh -lc 'export VAULT_ADDR=http://127.0.0.1:8200 && vault status'
kubectl get clusterrolebinding vault-server-binding
sops -d apps/hermes-agent/secrets/hermes-agent-secrets.sops.yaml
```

From inside the Vault pod shell:

```bash
vault auth list
vault secrets list
vault kv get kv/hermes-agent
vault policy read hermes-agent
vault read auth/kubernetes/role/hermes-agent
```
