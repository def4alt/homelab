#!/usr/bin/env bash
# Pull-based deploy of the vault stack on zorya, run by vault-deploy.timer as def4alt.
# git is the source of truth: fast-forward the checkout, decrypt secrets, converge compose.
set -euo pipefail

main() {
  local repo="${REPO:-$HOME/homelab}"
  local stack="$repo/hosts/zorya/vault"
  local secrets="${SECRETS_DIR:-$HOME/.local/state/vault}"
  export PATH="$HOME/.local/bin:$PATH" SECRETS_DIR="$secrets"
  export SOPS_AGE_KEY_FILE="${SOPS_AGE_KEY_FILE:-$HOME/.config/sops/age/keys.txt}"

  git -C "$repo" fetch -q origin main
  git -C "$repo" merge -q --ff-only origin/main

  install -d -m 700 "$secrets"
  umask 077
  for name in secrets.env silverbullet.env restic.env deploy_key; do
    [[ -f "$stack/secrets/$name.sops" ]] || continue  # restic.env arrives once the B2 key exists
    sops decrypt --input-type binary --output-type binary "$stack/secrets/$name.sops" > "$secrets/$name.new"
    mv "$secrets/$name.new" "$secrets/$name"
  done

  install -d /srv/vault-state/cache /srv/vault-state/mcp /srv/vault-state/caddy/data \
    /srv/vault-state/caddy/config /srv/vault-state/restic-cache
  docker compose -f "$stack/compose.yaml" up -d --wait --remove-orphans
}

# Read the whole script before running it: the merge above may rewrite this file.
main "$@"; exit
