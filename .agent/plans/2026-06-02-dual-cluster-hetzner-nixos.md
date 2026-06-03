# Dual-cluster homelab with a NixOS Hetzner host

This ExecPlan is a living document. The sections `Progress`, `Surprises & Discoveries`, `Decision Log`, and `Outcomes & Retrospective` must be kept up to date as work proceeds.

Reference: `/.agent/PLANS.md` from the repository root. This document must be maintained in accordance with PLANS.md.

## Purpose / Big Picture

After this change, the repository no longer describes only one NixOS host and one Kubernetes cluster. It describes two independent sites: the existing home host `perun` with the `clusters/home` Flux tree, and a new Hetzner host `zorya` with its own `clusters/hetzner` Flux tree. A novice should be able to inspect the repo and see where the Hetzner machine is installed from NixOS, where Flux for the Hetzner cluster lives, and which shared app manifests are intended to be reused by both clusters.

The observable proof for the repository work is local: `nix flake show ./nixos` should list both `perun` and `zorya`, `kubectl kustomize clusters/hetzner` should render a valid Flux tree for the second cluster, and the README should explain how to install and bootstrap each host. The in-cluster bootstrap and migration of public services remain separate operational steps because this repository change alone cannot SSH into the Hetzner host or apply manifests without credentials.

## Progress

- [x] (2026-06-02 18:20Z) Review the current single-host NixOS layout, the existing `clusters/home` Flux tree, and the historical Hetzner notes for `zorya`.
- [x] (2026-06-02 18:36Z) Refactor `nixos/` so the flake exposes both `perun` and `zorya` with host-specific hardware and disk layout modules.
- [x] (2026-06-02 18:37Z) Add a new `clusters/hetzner` Flux tree with bootstrap manifests and a minimal overlay set suitable for a second cluster.
- [x] (2026-06-02 18:37Z) Add a Hetzner-specific Traefik overlay so the edge cluster can bind public HTTP(S) ports without relying on MetalLB.
- [x] (2026-06-02 18:38Z) Update `README.md` so the repo no longer claims to be a single-host setup.
- [x] (2026-06-02 18:39Z) Validate the new NixOS flake and the new cluster overlays locally.
- [x] (2026-06-02 18:39Z) Document the remaining manual apply steps and the operational limits caused by missing remote credentials in this plan and the README.
- [x] (2026-06-03 07:55Z) Verify `zorya` from the Hetzner rescue environment, confirm the actual root-disk by-id path, and simplify the disk layout so `nixos-anywhere` does not depend on a missing attached volume.
- [x] (2026-06-03 08:05Z) Diagnose the failed first boot from the Hetzner console screenshot, confirm the VM is booting with SeaBIOS rather than UEFI, and switch the Hetzner host to a BIOS-safe GRUB + EF02 layout.

## Surprises & Discoveries

- Observation: The repo already contains a historical Hetzner hostname, `zorya`, in prior commits and in `.agent/plans/2026-05-15-zorya-boot-fix.md`, so reusing `zorya` is less surprising than inventing a new hostname.
  Evidence: `.agent/plans/2026-05-15-zorya-boot-fix.md` is explicitly about `zorya` on Hetzner, and earlier git history used the same hostname for the VPS bootstrap.

- Observation: The current `nixos/configuration.nix` is not a generic base module. It hard-codes the `perun` username, Longhorn host tweaks, Tailscale serve rules, and a single-cluster k3s assumption.
  Evidence: `nixos/configuration.nix` defines `users.users.perun`, enables `openiscsi`, installs the Longhorn `/usr/local/bin` symlink, and configures `tailscale serve` for ports `443` and `25565`.

- Observation: The shared Traefik HelmRelease is tuned for the home cluster because it exposes Traefik via a `LoadBalancer` service, which depends on MetalLB in this repository.
  Evidence: `apps/traefik/helmrelease.yaml` sets `spec.values.service.type` to `LoadBalancer`, and the home cluster overlay separately installs `apps/metallb` and `apps/metallb-config`.

- Observation: The existing Flux bootstrap manifests are generic enough to reuse for a second cluster with only the Git path changed.
  Evidence: Copying `clusters/home/flux-system/gotk-components.yaml` verbatim and changing only `gotk-sync.yaml.spec.path` to `./clusters/hetzner` still allowed `kubectl kustomize clusters/hetzner` to render successfully.

- Observation: The live Hetzner installer environment for `zorya` currently exposes only one writable install disk as `sda`, plus the mounted NixOS ISO as `sr0`.
  Evidence: `ssh nixos@46.62.137.102 'lsblk -o NAME,SIZE,TYPE,FSTYPE,LABEL,PARTLABEL,MOUNTPOINTS; ls -l /dev/disk/by-path'` showed `sda` with `disk-main-BIOS`, `disk-main-ESP`, and `disk-main-root`, and no second writable data disk.

- Observation: Hetzner Cloud is presenting `zorya` through SeaBIOS, so a pure `systemd-boot` EFI install hangs forever at "Booting from Hard Disk...".
  Evidence: the Hetzner console screenshot showed `SeaBIOS (version 1.16.3-...)` immediately before the hang, and the first reinstall produced only an EFI System partition plus Btrfs root with no BIOS boot partition.

## Decision Log

- Decision: Reuse `zorya` as the Hetzner hostname instead of inventing a new second-site host name.
  Rationale: The repository already carries `zorya` as the intended Hetzner identity, so reusing it reduces drift between historical plans and the new dual-cluster layout.
  Date/Author: 2026-06-02 / Codex

- Decision: Implement two independent single-node clusters, not a stretched cluster.
  Rationale: This matches the intended architecture discussed with the user: the home site and the Hetzner site should be separate failure domains and should not share Longhorn, k3s control-plane membership, or live database traffic across the WAN.
  Date/Author: 2026-06-02 / Codex

- Decision: Keep the first Hetzner cluster overlay intentionally small.
  Rationale: The user asked to set up the second cluster and NixOS host, not yet to migrate all public services. A minimal Flux tree with namespaces, cert-manager, and a Hetzner-shaped Traefik entry point is a safer first milestone than copying every home-cluster dependency.
  Date/Author: 2026-06-02 / Codex

- Decision: Install `zorya` onto the verified root disk only and place `/var/lib/rancher` on a Btrfs subvolume until a dedicated Hetzner volume is actually present.
  Rationale: The rescue environment has no attached `HC_Volume` block device today, so keeping the previous two-disk layout would make `nixos-anywhere` fail before installation even starts.
  Date/Author: 2026-06-03 / Codex

- Decision: Boot `zorya` with GRUB on GPT + EF02 instead of `systemd-boot`.
  Rationale: The host currently comes up under SeaBIOS, not UEFI, so BIOS-safe GRUB is the reliable option for this Hetzner VM.
  Date/Author: 2026-06-03 / Codex

## Outcomes & Retrospective

The repository now describes the two-site architecture at a structural level. `nixos/flake.nix` exposes both `perun` and `zorya`, `clusters/hetzner` exists alongside `clusters/home`, and the Hetzner cluster has its own Flux bootstrap tree plus a minimal overlay set. The README no longer claims the repository is only for one host.

What remains is operational rather than structural: `zorya` still needs to be reinstalled or installed with `nixos-anywhere`, Flux still needs to be applied to the Hetzner cluster, and application placement between the two clusters still needs a later migration plan. That separation is intentional because this session did not include live SSH or Kubernetes credentials for the Hetzner side.

## Context and Orientation

The repository currently has one Flux cluster tree under `clusters/home`. That tree contains `flux-system/` bootstrap manifests and `overlays/` with Flux `Kustomization` objects that point at directories under `apps/`. In this repository, a Flux `Kustomization` is a Kubernetes object that tells Flux to apply one directory from the Git repository. For example, `clusters/home/overlays/infra/traefik.yaml` tells Flux to reconcile `./apps/traefik`.

The NixOS source currently lives under `nixos/`. The file `nixos/flake.nix` exposes only one machine, `perun`. The file `nixos/configuration.nix` behaves like a shared machine configuration, but it still embeds `perun`-specific details such as the user name, Longhorn host requirements, and Tailscale serve rules.

The Hetzner side was only partially represented before this change. Earlier repository history used an Ubuntu VPS bootstrap for a host called `zorya`, and the repo still contains `.agent/plans/2026-05-15-zorya-boot-fix.md`, which confirms that `zorya` was already intended to become a NixOS host on Hetzner.

This plan does not migrate application ownership yet. It prepares the second host and the second cluster so later work can move selected public services onto Hetzner and route public traffic through it.

## Plan of Work

First, refactor `nixos/flake.nix` so it declares two hosts instead of one. Keep `nixos/configuration.nix` as the shared base module, but remove the hard-coded hardware import and parameterize the values that differ between hosts through `meta`. Add `nixos/hosts/zorya/hardware-configuration.nix` and `nixos/hosts/zorya/disko-config.nix` so the Hetzner host has a dedicated hardware profile and disk layout. Keep the existing root-level `nixos/hardware-configuration.nix` and `nixos/disko-config.nix` for `perun` to minimize churn.

Second, create `clusters/hetzner` by following the same structure as `clusters/home`: a `flux-system/` bootstrap directory, a root `kustomization.yaml`, a `modes/` directory, and an `overlays/` directory. The new overlay set should be intentionally small: namespaces, cert-manager, cert-manager issuers, and Traefik. Copy the home Flux bootstrap manifests for consistency, then change only the Git path in `gotk-sync.yaml` to `./clusters/hetzner`.

Third, add a Hetzner-specific Traefik overlay under `apps/modes/hetzner/traefik`. This overlay should patch the shared Traefik HelmRelease so the Hetzner cluster does not depend on MetalLB. The expected shape is a host-networked ingress controller that binds ports `80` and `443` directly on the single Hetzner node while keeping an internal ClusterIP service for in-cluster routing.

Fourth, update `README.md` so the installation and Kubernetes sections describe both hosts and both clusters. The README should spell out how to install `perun` and `zorya`, how to bootstrap Flux for the Hetzner cluster, and which work is still manual because the repository does not contain live credentials.

## Concrete Steps

All commands are run from `/Users/def4alt/source/homelab`.

1. Inspect the current repository shape and confirm the home-only assumptions:

    find clusters -maxdepth 3 -type f | sort
    find apps -maxdepth 2 -type f | sort
    read nixos/flake.nix
    read nixos/configuration.nix

2. Refactor the NixOS flake and add the Hetzner host files.

3. Create `clusters/hetzner` by copying the Flux bootstrap structure from `clusters/home` and trimming the overlays to the minimal second-cluster set.

4. Add `apps/modes/hetzner/traefik/kustomization.yaml` so the Hetzner cluster uses a direct public Traefik configuration instead of the home-cluster `LoadBalancer` setup.

5. Update `README.md` to document the dual-cluster layout and the install/bootstrap commands.

6. Validate locally:

    nix flake show ./nixos
    kubectl kustomize apps/modes/hetzner/traefik >/dev/null
    kubectl kustomize clusters/hetzner >/dev/null
    kubectl kustomize clusters/home >/dev/null

7. If local validation fails, keep iterating until all four commands succeed or until a failure is proven to require remote credentials that are not available in this session.

## Validation and Acceptance

Repository acceptance is complete when all of the following are true:

- `nix flake show ./nixos` lists both `perun` and `zorya` under `nixosConfigurations`.
- `kubectl kustomize apps/modes/hetzner/traefik` renders a patched Traefik HelmRelease without syntax errors.
- `kubectl kustomize clusters/hetzner` renders a valid Flux tree for the second cluster.
- `kubectl kustomize clusters/home` still renders, proving the home cluster was not broken by the refactor.
- `README.md` no longer says the repo represents only a single NixOS host.

Operational acceptance is intentionally separate and must be done later with credentials:

- `nixos-anywhere --flake .#zorya root@46.62.137.102` installs the Hetzner host.
- `kubectl apply -k clusters/hetzner/flux-system` or `flux bootstrap ... --path=clusters/hetzner` bootstraps Flux on the second cluster.
- The Hetzner node becomes `Ready` and Flux reconciles the minimal overlay set.

## Idempotence and Recovery

The repository edits are safe to repeat. Re-running the local validation commands should not mutate state. If a file move or refactor breaks the repo, recover with `git checkout -- <path>` for individual files or `git restore .` for the working tree before trying again.

The dangerous operations are the later remote ones: reinstalling `zorya` with `nixos-anywhere` will replace the existing operating system on `46.62.137.102`, and applying `clusters/hetzner/flux-system` to a live cluster will make Flux own that cluster. Those steps are not part of this repository-only implementation and must not be attempted without explicit remote access and backups.

## Artifacts and Notes

Expected local proof snippets at the end of the repository work should look like this:

    $ nix flake show ./nixos
    ...
    └───nixosConfigurations
        ├───perun: NixOS configuration
        └───zorya: NixOS configuration

    $ kubectl kustomize clusters/hetzner >/dev/null && echo ok
    ok

## Interfaces and Dependencies

The NixOS flake must continue to live at `nixos/flake.nix`, because the README and operator workflows already point there. The home cluster must continue to reconcile from `clusters/home`, and the new Hetzner cluster must reconcile from `clusters/hetzner`.

The Hetzner Traefik overlay must remain a Kustomize overlay under `apps/modes/hetzner/traefik` so it can reuse the shared `apps/traefik` manifests while changing only the Hetzner-specific HelmRelease values. That keeps one source of truth for the chart repository and most chart defaults.

The new host name must be `zorya`, and the second cluster path must be `clusters/hetzner`, because those names are already used in the repository history and in the architecture discussion that motivated this change.

Change note: Initial plan created to add a second NixOS host (`zorya`) and a second Flux cluster tree (`clusters/hetzner`) without yet migrating application placement or performing remote installation.
Change note: Updated after implementation to record the completed repository refactor, local validation results, and the remaining manual apply steps.
Change note: Updated after removing the obsolete `hetzner-hermes/` Ubuntu bootstrap so the plan no longer points at deleted files.
Change note: Updated after regenerating `zorya` hardware config from the live Hetzner installer, switching the disko whole-disk target to `/dev/sda`, and assigning the Hetzner SSH key to `zorya`.
Change note: Updated `zorya` to use the same hashed password as `perun` and removed the invalid shared `services.k3s.tokenFile` setting so single-node cluster init can complete after install.
Change note: Updated the shared k3s config to support per-host `token` / `tokenFile`, and temporarily set a literal bootstrap token on `zorya` for installation.
Change note: Adjusted the Hetzner Flux bootstrap to pull the public GitHub repo without a bootstrap auth secret, so `clusters/hetzner/flux-system` can be applied directly after install.