# Home cluster modes

The home cluster supports two GitOps modes:

- `minecraft`: keeps Minecraft on and forces Hermes Agent, Immich, Paperless, and Kaneo app deployments off
- `apps`: keeps those app deployments on and forces Minecraft off

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

- `clusters/home/modes/apps/` patches the Flux Minecraft Kustomization to use `apps/modes/apps/minecraft`
- `clusters/home/modes/minecraft/` patches the Flux Hermes/Immich/Paperless/Kaneo Kustomizations to use `apps/modes/minecraft/*`
- `apps/modes/**` reuse the base app manifests and only patch replica counts

## Database caveat

This mode system only switches Deployments and the Minecraft HelmRelease replica count.
CloudNativePG clusters for Immich, Paperless, and Kaneo are not part of the mode switch because CNPG requires `spec.instances >= 1`.
