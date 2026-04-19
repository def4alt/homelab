# Storage Provisioning

This OpenTofu root provisions the external storage pieces for the homelab:

- an AWS S3 bucket for CNPG/Barman backups under the shared `cnpg/` prefix with Glacier Deep Archive lifecycle rules
- a Backblaze B2 bucket for the live Immich media library used by JuiceFS
- a restricted B2 application key for JuiceFS
- a restricted AWS IAM user and access key for backup writes

## Usage

1. Copy `terraform.tfvars.example` to `terraform.tfvars` and adjust the names or region if needed.
2. Export AWS credentials for the target account, or use an AWS profile.
3. Run:

```sh
cd storage
tofu fmt -recursive
tofu init
tofu apply
```

## Outputs

After apply, use `tofu output` to populate the Kubernetes SOPS secrets for:

- CNPG backup writes to AWS S3 / Glacier Deep Archive
- JuiceFS access to Backblaze B2

The backup bucket uses a 1-day transition to Deep Archive and a 181-day expiration so objects under `cnpg/` spend at least 180 days in the cold tier.
