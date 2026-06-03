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
            enableLonghornHostTweaks = true;
            enableOpeniscsi = true;
            enableTailscalePublicTcp = true;
            enableQemuGuest = false;
            firewallEnable = false;
            firewallTCPPorts = [ ];
            k3sExtraFlags = [
              "--disable local-storage"
            ];
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
            enableLonghornHostTweaks = false;
            enableOpeniscsi = false;
            enableTailscalePublicTcp = false;
            enableQemuGuest = true;
            firewallEnable = true;
            firewallTCPPorts = [ 22 80 443 ];
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
