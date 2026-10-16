# Knowledge vault on zorya (Contabo)

Docker Compose stack for the vault (see `compose.yaml`): Caddy on 80/443 for `vault.def4alt.com`, the
vault server (`mcp`) and `worker` behind it, SilverBullet on the tailnet, Syncthing for the Mac and the
perun replica, and a restic `backup` job. Code: github.com/def4alt/vault-mcp.

```
/srv/vault          git repo: pages + blobs/ (canonical; pushed to github.com/def4alt/vault)
/srv/documents      documents tree (Agent/inbox is the drop folder)
/srv/vault-state    derived and runtime state: index cache, OAuth registrations, Caddy certificates
~/.local/state/vault  decrypted secrets (0700), written by deploy.sh
```

## Deploying

`vault-deploy.timer` (systemd user unit, every 5 min) runs `deploy.sh`: fast-forward `~/homelab`, decrypt
`secrets/*.sops` with zorya's age key (`~/.config/sops/age/keys.txt`, only on zorya), and
`docker compose up -d --wait --remove-orphans`. Change the stack by committing here.

Secrets are binary SOPS files encrypted to zorya's age key (`.sops.yaml`). To replace one from the Mac,
with the new content on the clipboard:

```bash
pbpaste | sops encrypt --input-type binary --output-type binary --filename-override hosts/zorya/vault/secrets/restic.env.sops /dev/stdin > hosts/zorya/vault/secrets/restic.env.sops
```

| File | Holds |
|---|---|
| `secrets.env` | `GITHUB_CLIENT_ID`, `GITHUB_CLIENT_SECRET`, `JWT_SIGNING_KEY`, `LINK_SECRET`, `API_KEYS` |
| `silverbullet.env` | `SB_USER` |
| `restic.env` | `RESTIC_REPOSITORY=b2:def4alt-homelab-documents:/`, `RESTIC_PASSWORD`, `B2_ACCOUNT_ID`, `B2_ACCOUNT_KEY` (a key without `deleteFiles`) |
| `deploy_key` | write deploy key for github.com/def4alt/vault |

## First install

```bash
sudo install -d -o def4alt -g def4alt /srv/vault /srv/documents /srv/vault-state
git clone https://github.com/def4alt/homelab ~/homelab
cp ~/homelab/hosts/zorya/vault/systemd/* ~/.config/systemd/user/
systemctl --user daemon-reload && systemctl --user enable --now vault-deploy.timer vault-backup.timer
tailscale serve --bg --https=8444 http://127.0.0.1:3000   # SilverBullet on the tailnet
```

The Hetzner Cloud Firewall allows inbound 80/tcp, 443/tcp and 443/udp only (Docker-published ports
bypass ufw); SSH is reached over Tailscale.

## Operating

- Logs: `docker compose -f ~/homelab/hosts/zorya/vault/compose.yaml logs -f mcp worker caddy`
- Failed timers log `vault: <unit> failed` at priority err: `journalctl --user -p err`
- Rebuild the index: `docker compose ... exec worker vault-index --rebuild`
- Lint findings: the `problems` table (`sql` tool) or `docker compose ... exec worker vault-lint /vault`
- Restore: restic snapshots tagged `zorya` (perun prunes and runs the monthly restore drill).
