{
  description = "Homelab NixOS Flake";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05";
    disko.url = "github:nix-community/disko";
    disko.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { nixpkgs, disko, ... }:
    let
      mkHost = { name, meta, modules, system ? "x86_64-linux" }: {
        inherit name;
        value = nixpkgs.lib.nixosSystem {
          inherit system;
          specialArgs = {
            inherit meta;
          };
          modules = [ disko.nixosModules.disko ] ++ modules;
        };
      };

      hosts = [
        (mkHost {
          name = "perun";
          meta = {
            hostname = "perun";
            primaryUser = "perun";
            userGroups = [ "wheel" "docker" "dialout" "tty" "uucp" ];
            hashedPassword = "$6$CaCEWrNfJLit0lxA$ZUyRUZH9Vy6hlCseXfyRuz2KxYTtrAieGUqWRnpEnnJA3PdbJE8M.kmn6JKyMlYHRu7yNfvlM1F7oT7efwp7l.";
            authorizedKeys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFh6m4qX4U4sYAI+ngMuLACi4pqSz2pNjdPcB8aEzD6k"
            ];
            enableLonghornHostTweaks = false;
            enableOpeniscsi = false;
            enableTailscalePublicTcp = true;
            enableQemuGuest = false;
            enableDokploy = true;
            useGrub = false;
            firewallEnable = true;
            firewallTCPPorts = [ ];
            firewallUDPPorts = [ 41641 ];
            firewallTrustedInterfaces = [ "cni0" "flannel.1" "tailscale0" ];
            firewallInterfaces.eno1 = {
              allowedTCPPorts = [ 22 53 80 443 6443 8123 18555 21064 25565 ];
              allowedUDPPorts = [ 53 8472 1900 5353 ];
            };
            enableK3s = true;
            k3sExtraFlags = [ ];
          };
          modules = [
            ./hardware-configuration.nix
            ./disko-config.nix
            ./configuration.nix
          ];
        })
        (mkHost {
          name = "zorya";
          meta = {
            hostname = "zorya";
            primaryUser = "def4alt";
            userGroups = [ "wheel" "docker" ];
            hashedPassword = "$6$CaCEWrNfJLit0lxA$ZUyRUZH9Vy6hlCseXfyRuz2KxYTtrAieGUqWRnpEnnJA3PdbJE8M.kmn6JKyMlYHRu7yNfvlM1F7oT7efwp7l.";
            authorizedKeys = [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJHkn9VZPfLdE+bJtPkHEK/k4fZNc1M8coHxC4HAU+JV"
            ];
            enableLonghornHostTweaks = false;
            enableOpeniscsi = false;
            enableTailscalePublicTcp = false;
            enableQemuGuest = true;
            enableDokploy = false;
            useGrub = true;
            firewallEnable = true;
            firewallTCPPorts = [ 22 ];
            enableK3s = false;
            k3sTokenFile = "/var/lib/rancher/k3s/server/token";
            k3sExtraFlags = [ ];
          };
          modules = [
            ./hosts/zorya/hardware-configuration.nix
            ./hosts/zorya/disko-config.nix
            ./configuration.nix
          ];
        })
      ];
    in {
      nixosConfigurations = builtins.listToAttrs hosts;
    };
}
