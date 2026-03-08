# Executor

## Database bootstrap

The app expects an existing PostgreSQL database and user:

- database: `executor`
- user: `executor`
- password: stored in `secrets/executor-secrets.sops.yaml`

Create them before letting Flux deploy the app.

Example SQL:

```sql
CREATE USER executor WITH PASSWORD '<set-to-decrypted-secret-password>';
CREATE DATABASE executor OWNER executor;
GRANT ALL PRIVILEGES ON DATABASE executor TO executor;
```

The deployment builds its JDBC URL from these non-secret defaults:

- host: `postgres-rw`
- port: `5432`
- database: `executor`

If your writable Postgres service has a different DNS name, update `deployment.yaml`.
