# Harden perun k3s secrets, host firewall, and workload networking

## Goal

Reduce the impact of disk access, exposed host listeners, and a compromised workload by enabling Kubernetes Secret encryption at rest, enabling a narrowly scoped NixOS firewall, and introducing default-deny NetworkPolicies without disrupting perun's homelab services.

## Scope and approach

This change has three staged controls with independent verification and rollback:

1. Add `--secrets-encryption` to k3s, rebuild perun, verify the node and Flux recover, then run `k3s secrets-encrypt reencrypt` and verify the encryption status.
2. Enable the NixOS firewall. Trust only loopback/CNI traffic, permit Tailscale administration, and allow only required LAN service/API ports on `eno1`. Verify SSH through both Tailscale and LAN, API reachability from allowed networks, denial of sensitive listeners, MetalLB services, DNS, ingress, Minecraft, Home Assistant, and pod networking.
3. Introduce NetworkPolicies incrementally. Begin with the low-dependency Blog namespace using deny-by-default ingress and egress plus explicit Traefik and DNS access. Add ingress isolation to Glance and Paperless with explicit Traefik, same-namespace, and CNPG-operator paths while initially retaining egress to avoid breaking integrations. Validate each namespace before extending the pattern.

## Inventory

- Perun LAN interface/address: `eno1`, `192.168.88.189/24`.
- Perun Tailscale interface/address: `tailscale0`, `100.119.240.70`.
- Pod networking: `cni0` and `flannel.1`, pod CIDR `10.42.0.0/24`.
- Kubernetes API currently listens on all addresses at TCP `6443`.
- etcd listens on the LAN address at TCP `2379` and `2380`; these must not be opened by the firewall.
- Required LAN LoadBalancer ports are DNS TCP/UDP `53`, ingress TCP `80/443`, and Minecraft TCP `25565`.
- Required host administration ports are SSH TCP `22` and Kubernetes API TCP `6443` on the LAN and tailnet.
- K3s Secret encryption is currently disabled.
- Existing NetworkPolicies are limited to `flux-system`.

## Progress

- [x] (2026-07-17) Inventory interfaces, listeners, LoadBalancer/NodePort services, existing policies, and encryption status.
- [x] (2026-07-17) Add `--secrets-encryption`; the NixOS flake evaluation passes. A full local build is unavailable because the operator workstation is `aarch64-darwin`, so build on perun before activation.
- [x] (2026-07-17) Build and activate the encryption configuration on perun; verify fresh key-only SSH, k3s, the Ready node, and all Flux Kustomizations recover.
- [x] (2026-07-17) Run dynamic key rotation/re-encryption. Status is enabled at `reencrypt_finished`, all server hashes match, and the new AES-CBC key is active.
- [x] (2026-07-17) Add the declarative NixOS firewall configuration and validate the evaluated interface/port sets.
- [x] (2026-07-17) Activate the firewall and verify fresh LAN/Tailscale SSH, API access, LAN DNS/ingress/Home Assistant, public endpoints, pod health, and denial of LAN etcd, kubelet, and node-exporter access. Activation reported a pre-existing D-Bus reload timeout, but the new generation and firewall are active and D-Bus remains healthy.
- [x] (2026-07-17) Add the first incremental NetworkPolicy set for Blog, Glance, and Paperless.
- [ ] Reconcile and test every isolated namespace.
- [ ] Document results, limitations, and the next policy rollout.

## Firewall design

- Trust `lo`, `cni0`, and `flannel.1` so local Kubernetes networking is not broken.
- Permit Tailscale traffic through `tailscale0`; the tailnet remains an administrative trust boundary governed by Tailscale ACLs.
- On `eno1`, allow TCP `22`, `53`, `80`, `443`, `6443`, `8123`, and `25565`; allow UDP `53`, `8472`, and the Home Assistant discovery ports that are confirmed necessary.
- Allow Tailscale's UDP transport port globally.
- Do not allow LAN access to etcd `2379/2380`, kubelet `10250`, metrics endpoints, FRR management ports, or other host-network listeners.
- Keep an established SSH session open during activation and verify a second fresh connection before closing it.

## NetworkPolicy design

- Use namespace labels (`kubernetes.io/metadata.name`) rather than mutable custom labels.
- Blog: default deny ingress and egress; permit ingress from `infra` to the pod's TCP `8080`, and DNS egress to kube-dns.
- Glance: default deny ingress; permit ingress from `infra` to the pod's TCP `8080`. Preserve egress initially because Glance aggregates external and internal services.
- Paperless: default deny ingress; permit ingress from `infra` to TCP `8000`, same-namespace application/database traffic, and CNPG operator traffic. Preserve egress initially for backups and integrations.
- Do not broadly apply policies to infrastructure, privileged storage, monitoring, or home-automation namespaces until their flows are separately inventoried.

## Validation

- `nix flake check` and `nix build .#nixosConfigurations.perun.config.system.build.toplevel` pass.
- A fresh key-only Tailscale SSH connection succeeds after each rebuild.
- `k3s kubectl get nodes` reports perun Ready and all Flux Kustomizations return Ready.
- `k3s secrets-encrypt status` reports encryption enabled and existing Secrets re-encrypted.
- LAN and Tailscale API access succeeds; unauthorized host listeners remain blocked from LAN.
- `def4alt.com`, Authentik, Dashboard, and Papers return expected responses.
- Pi-hole DNS, Minecraft, Home Assistant, Cloudflare Tunnel, CNPG clusters, and backup resources remain healthy.
- Blog, Glance, and Paperless remain reachable after policy reconciliation; denied cross-namespace probes fail.

## Rollback

- Keep the previous NixOS generation available and use `nixos-rebuild switch --rollback` from the retained SSH session if firewall activation interrupts required traffic.
- Remove or suspend a newly added NetworkPolicy through Git revert and Flux reconciliation; if necessary, delete only that policy live to restore service while preserving GitOps as the source of truth.
- Do not remove the k3s encryption flag after Secrets are encrypted. If encryption rollout fails, stop before re-encryption and restore the previous generation; after re-encryption, repair encryption configuration rather than disabling it.
