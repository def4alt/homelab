# Home cluster modes

The home cluster supports two GitOps modes:

- `minecraft`: keeps Minecraft on and forces Immich and Paperless app
  deployments off
- `apps`: keeps Immich and Paperless on and forces Minecraft off

The active mode is selected in `clusters/home/kustomization.yaml`.

## Switch modes

Use the helper script from the repo root:

```bash
./scripts/switch-mode minecraft
./scripts/switch-mode apps
```

Then commit and push the mode change so Flux can reconcile it:

```bash
git add clusters/home/kustomization.yaml
git commit -m "feat(home): switch to minecraft mode"
git push origin main
```

## Mode implementation

- `clusters/home/modes/apps/` patches the Flux Minecraft Kustomization to use
  `apps/modes/apps/minecraft`
- `clusters/home/modes/minecraft/` patches the Flux Immich and Paperless
  Kustomizations to use `apps/modes/minecraft/*`
- `apps/modes/**` reuse the base app manifests and only patch replica counts

## Database caveat

This mode system only switches Deployments and the Minecraft HelmRelease replica
count. CloudNativePG clusters for Immich and Paperless are not part of the mode
switch because CNPG requires `spec.instances >= 1`.
