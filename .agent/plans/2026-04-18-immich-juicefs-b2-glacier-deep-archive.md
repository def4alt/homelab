# Immich JuiceFS + B2 + Glacier Deep Archive Implementation Plan

> **For implementation:** REQUIRED SUB-SKILL: Use superpowers:executing-plans to implement this plan task-by-task.

**Goal:** Move the Immich media library onto JuiceFS backed by Backblaze B2, and move Immich PostgreSQL backups onto AWS S3 Glacier Deep Archive with a 180-day minimum storage period.

**Architecture:** Keep Immich’s app, ingress, and CNPG database pattern, but replace the live media PVC with a JuiceFS-backed filesystem so the library stays online while the bulk data lives in B2. Use OpenTofu to provision the storage backends and credentials: one B2 bucket/app key for JuiceFS and one AWS S3 bucket for archival database backups. Keep the runtime secrets in SOPS-managed Kubernetes secrets. The cutover happens in two steps: first the library move, then the backup target switch, with the old Longhorn volume preserved until the JuiceFS path is verified.

**Tech Stack:** Kubernetes/k3s, Flux, OpenTofu, JuiceFS CSI driver, Backblaze B2, AWS S3 Glacier Deep Archive, CloudNativePG, SOPS, NixOS.

---

## Progress

- [x] Plan written.
- [x] (2026-04-18) Added a `storage/` OpenTofu root for the AWS backup bucket and Backblaze B2 library bucket.
- [x] (2026-04-18) Added the JuiceFS CSI driver, namespace, metadata DB, storage class, and staged Immich cutover manifests.
- [x] (2026-04-18) Immich database backup cadence updated to once every day and retention set to 180d in the repo.
- [x] OpenTofu storage project created.
- [x] JuiceFS storage layer scaffolded in repo.
- [ ] JuiceFS storage layer deployed.
- [ ] Immich media cut over to JuiceFS.
- [ ] Immich CNPG backups switched to Glacier Deep Archive.
- [ ] Migration validated in-cluster.

## Decision Log

- Decision: Use JuiceFS instead of SeaweedFS.
  Rationale: JuiceFS is the simpler fit for presenting one online filesystem path to Immich while pushing bulk media to object storage.

- Decision: Use Backblaze B2 for the live Immich library.
  Rationale: The library needs to stay immediately accessible; B2 is always-hot object storage and is better suited than Glacier for active reads.

- Decision: Use AWS S3 Glacier Deep Archive for Immich database backups.
  Rationale: Database backups are infrequently restored and can tolerate cold storage, while the 180-day minimum storage period avoids early-deletion penalties.

- Decision: Keep the live library and the backup archive separate.
  Rationale: Immich needs online storage for originals, while Glacier Deep Archive is only suitable for backup copies.

## Surprises & Discoveries

- JuiceFS needs a metadata backend; the safest homelab fit is a small dedicated CNPG Postgres database.
- The current Immich library is a Longhorn PVC, so the migration will need a temporary data copy before the claim switch.
- Glacier Deep Archive is only appropriate for the backup copy, not the active library path.

## Plan of Work

### Task 1: Add OpenTofu storage project

**Files:**
- Create: `storage/versions.tf`
- Create: `storage/providers.tf`
- Create: `storage/variables.tf`
- Create: `storage/main.tf`
- Create: `storage/outputs.tf`
- Create: `storage/terraform.tfvars.example`
- Create: `storage/README.md`

**Step 1: Define the storage inputs and providers**

Create one OpenTofu root that can manage both backends:
- AWS provider for the archival Immich backup bucket
- Backblaze B2 provider for the JuiceFS library bucket and app key

Keep all credentials external via environment variables or a local `terraform.tfvars` file.

**Step 2: Add the AWS archival bucket**

Provision an S3 bucket for Immich database backups with:
- versioning enabled if it helps recovery workflows
- lifecycle rules that transition objects to `GLACIER_DEEP_ARCHIVE`
- expiration at `180d` or later to satisfy the minimum storage period
- a dedicated, restricted IAM principal for backup writes

**Step 3: Add the B2 bucket for JuiceFS**

Provision a B2 bucket dedicated to the Immich media library and a restricted app key for JuiceFS.

**Step 4: Add outputs**

Expose the bucket names, regions/endpoints, and credential identifiers needed to generate the Kubernetes secrets.

**Step 5: Verify the OpenTofu project**

Run:
```sh
cd storage
tofu fmt -recursive
tofu init
tofu plan
```
Expected: the project initializes cleanly and the plan shows the two storage backends.

---

### Task 2: Add SOPS-managed runtime secrets

**Files:**
- Create: `apps/immich/secrets/juicefs-b2.sops.yaml`
- Create: `apps/immich/secrets/immich-backup-aws.sops.yaml`
- Modify: `apps/immich/kustomization.yaml`

**Step 1: Add the JuiceFS secret**

Store the B2 app key and JuiceFS connection details as a Kubernetes secret. Keep the file encrypted with SOPS so Flux can decrypt it in-cluster.

**Step 2: Add the AWS backup secret**

Store the AWS access key material needed by CNPG/Barman in a separate SOPS-managed secret.

**Step 3: Wire the secrets into Immich**

Update the Immich kustomization so the app sees both secrets.

**Step 4: Verify the manifests**

Run:
```sh
kubectl kustomize apps/immich
```
Expected: the secret manifests render without errors.

---

### Task 3: Deploy JuiceFS in Kubernetes

**Files:**
- Create: `apps/juicefs/kustomization.yaml`
- Create: `apps/juicefs/helmrepository.yaml` or equivalent source manifest
- Create: `apps/juicefs/helmrelease.yaml`
- Create: `apps/juicefs/storageclass.yaml`
- Create: `apps/namespaces/namespace-juicefs.yaml`
- Modify: `apps/namespaces/kustomization.yaml`
- Create: `clusters/home/overlays/infra/juicefs.yaml`
- Modify: `clusters/home/overlays/kustomization.yaml`

**Step 1: Add the JuiceFS controller**

Deploy the JuiceFS CSI driver via Flux so Kubernetes can provision a JuiceFS-backed volume using cluster-managed secrets.

**Step 2: Add the JuiceFS metadata database**

Create a small CNPG cluster dedicated to JuiceFS metadata. Keep it separate from the Immich application database so the storage layer can be recovered independently.

**Step 3: Add the JuiceFS StorageClass**

Create a StorageClass that references:
- the JuiceFS metadata URL
- the B2 credentials secret
- the new B2 bucket

**Step 4: Verify the manifests**

Run:
```sh
kubectl kustomize apps/juicefs
kubectl kustomize clusters/home/overlays
```
Expected: both render successfully and Flux can reconcile the new objects.

---

### Task 4: Switch Immich media storage to JuiceFS

**Files:**
- Modify: `apps/immich/pvc.yaml`
- Modify: `apps/immich/server-deployment.yaml` if mount paths need adjustment
- Create: `apps/immich/migration-job.yaml` or similar one-shot copy job
- Modify: `apps/immich/kustomization.yaml`

**Step 1: Replace the Longhorn-backed library claim**

Keep the PVC name `immich-library`, but change it to use the JuiceFS StorageClass.

**Step 2: Copy existing media into JuiceFS**

Add a one-shot migration job that:
- mounts the old Longhorn PVC read-only
- mounts the new JuiceFS-backed PVC read-write
- copies the Immich library contents across
- preserves ownership and timestamps

**Step 3: Cut over the Deployment**

After the copy is verified, point the Immich server at the JuiceFS-backed claim and scale the app back up.

**Step 4: Verify the cutover**

Run:
```sh
kubectl -n immich rollout status deploy/immich-server
kubectl -n immich exec deploy/immich-server -- test -d /data
```
Expected: the app starts cleanly and `/data` is present on the JuiceFS mount.

---

### Task 5: Move Immich CNPG backups to Glacier Deep Archive

**Status:**
- Immich now reuses the shared `cnpg-barman-aws` secret from `apps/secrets`.
- The Immich Barman object store points at the AWS backup bucket in `eu-west-1`.
- The scheduled backup remains daily.

**Files:**
- Modify: `apps/immich/barman-objectstore.yaml`
- Modify: `apps/immich/scheduled-backup.yaml` if the cadence changes later
- Modify: `apps/immich/postgres-cluster.yaml` if the plugin parameters change
- Modify: `apps/immich/kustomization.yaml`
- Reuse: `apps/secrets/cnpg-barman-s3.sops.yaml` as the shared AWS-backed CNPG secret

**Step 1: Point the backup target at AWS**

Switch the Immich Barman object store from the current B2 endpoint to the AWS S3 bucket created by OpenTofu.

**Step 2: Apply the Glacier lifecycle policy**

Ensure the bucket lifecycle transitions backup objects to `GLACIER_DEEP_ARCHIVE` and keeps them for at least `180d`.

**Step 2b: Keep the CNPG backup cadence daily**

Retain the daily Immich scheduled backup so the RPO stays tight.

**Step 3: Keep the CNPG plugin wiring intact**

Do not change the database engine or the plugin flow; only change the remote object store and retention policy.

**Step 4: Verify the backup target**

Run:
```sh
kubectl -n immich get objectstore,barmanobjectstore,scheduledbackup
kubectl -n immich describe cluster immich-db
```
Expected: the CNPG plugin reports the new backup target and no reconciliation errors.

---

### Task 6: Validate migration and clean up

**Files:**
- Modify: `README.md`
- Optionally modify: `.agent/plans/2026-04-18-immich-tailnet-upload-routing.md` if the status summary should mention the storage change

**Step 1: Reconcile Flux**

Run:
```sh
flux reconcile kustomization flux-system --with-source
flux reconcile kustomization immich --with-source
```
Expected: Flux applies the new storage manifests.

**Step 2: Validate the live paths**

Check that:
- Immich serves normally
- uploads still work
- the library is readable from the JuiceFS mount
- the CNPG backup target points at the Glacier bucket

**Step 3: Keep the old Longhorn PVC until confidence is high**

Do not delete the old volume until the new library has been verified and the backup target has completed at least one successful cycle.

**Step 4: Document the new split**

Update the README with the final architecture:
- B2 for the live Immich library via JuiceFS
- Glacier Deep Archive for Immich database backups
- 180-day minimum retention for the archive bucket

---

## Validation and Acceptance

After implementation, the expected outcomes are:

- Immich media is stored on JuiceFS backed by B2 and remains online.
- Immich database backups go to AWS S3 Glacier Deep Archive.
- The Glacier bucket has a 180-day minimum storage period.
- Flux reconciles without errors.
- The old Longhorn library volume can be retired only after successful validation.

## Rollback Plan

If the JuiceFS cutover fails, restore the Immich Deployment to the Longhorn-backed PVC and reapply the previous manifests. If the Glacier backup target fails, revert the CNPG object store config to the previous backup target before deleting any existing archive data.

## Notes

- Keep this change scoped to Immich only.
- Do not change the existing backup strategy for unrelated apps.
- Treat the media cutover and the database backup cutover as separate steps so each can be rolled back independently.
