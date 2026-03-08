# Executor

## Database

`executor` uses a dedicated CloudNativePG cluster in this namespace, following the same pattern as the other database-backed apps in the homelab.

- cluster: `executor-db`
- database: `executor`
- owner: `executor`
- writable service: `executor-db-rw`

Credential sources:

- `secrets/postgres-auth.sops.yaml` bootstraps the CNPG database owner
- `secrets/executor-secrets.sops.yaml` provides the same username/password to the Spring app
