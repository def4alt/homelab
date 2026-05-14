# Hermes VPS — Hetzner

Provisions a single Hetzner VM running **only** the official Hermes install, with persistent state on an attached data volume, automatic daily updates via `hermes update`, and PDF skill dependencies preinstalled.

## Usage

```bash
# 1. Prepare your vars
cp terraform.tfvars.example terraform.tfvars
# edit terraform.tfvars with your Hetzner token and SSH key

# 2. Provision
terraform init
terraform apply

# 3. Migrate existing Hermes data
ssh root@$(terraform output -raw server_ipv4)
# confirm /srv/hermes-data is mounted and Hermes is installed for /home/hermes

# Then from your local machine, after stopping Hermes on the old host:
rsync -avz --delete old-server:~/.hermes/ root@NEW_IPV4:/srv/hermes-data/.hermes/
ssh root@NEW_IPV4 chown -R hermes:hermes /srv/hermes-data/.hermes

# 4. Enable and start Hermes after the migration completes
ssh root@NEW_IPV4 systemctl enable --now hermes.service
ssh root@NEW_IPV4 journalctl -fu hermes.service

# 5. For a fresh install instead of a migration
ssh root@NEW_IPV4 'su - hermes -c "bash -lc \"hermes setup\""'
```

## Included tool dependencies

The bootstrap also installs the PDF skill prerequisites:
- CLI: `qpdf`, `pdftotext`, `pdfimages`, `tesseract`
- Python: `pypdf`, `pdfplumber`, `reportlab`, `pytesseract`, `pdf2image`, `pandas`, `openpyxl`

## Services on the VPS

| Service | Description |
|---|---|
| `hermes.service` | Runs `hermes gateway` as the `hermes` user |
| `hermes-update.timer` | Runs `hermes update` daily at a random hour |
| `ufw` | Deny all inbound except SSH |

## Security

- No ports other than SSH are opened by the Hetzner firewall or UFW.
- Hermes state lives at `/srv/hermes-data/.hermes`, symlinked to `/home/hermes/.hermes`.
- Set `allowed_ssh_cidrs` to the IP ranges you actually use for SSH. If you want IPv6-only restrictions, use IPv6 CIDRs like `YOUR_IPV6/128`.
