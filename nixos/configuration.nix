{ pkgs, meta, ... }:

{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
    ];

  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = meta.hostname; # Define your hostname.
  # Pick only one of the below networking options.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.
  networking.networkmanager.enable = true;  # Easiest to use and most distros use this by default.

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    #useXkbConfig = true; # use xkb.options in tty.
  };

  # Fixes for longhorn
  systemd.tmpfiles.rules = [
    "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
  ];
  virtualisation.docker.logDriver = "json-file";

  services.openiscsi = {
    enable = true;
    name = "iqn.2016-04.com.open-iscsi:${meta.hostname}";
  };

  services.tailscale.enable = true;

  systemd.services.tailscale-public-tcp = {
    description = "Expose api-photos.def4alt.com, minecraft.def4alt.com, and shell.def4alt.com over Tailscale";
    after = [
      "network-online.target"
      "tailscaled.service"
    ];
    wants = [
      "network-online.target"
      "tailscaled.service"
    ];
    wantedBy = [ "multi-user.target" ];
    path = with pkgs; [ coreutils gnugrep tailscale ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      set -euo pipefail

      for _ in $(seq 1 60); do
        if tailscale status --json | grep -Eq '"BackendState": *"Running"'; then
          tailscale serve reset >/dev/null 2>&1 || true
          tailscale serve --bg --yes --tcp=443 tcp://127.0.0.1:31818
          tailscale serve --bg --yes --tcp=25565 tcp://127.0.0.1:31697
          tailscale serve --bg --yes --tls=false --tcp=22 tcp://127.0.0.1:31022
          exit 0
        fi

        sleep 2
      done

      exit 1
    '';
  };


  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.perun = {
    isNormalUser = true;
    extraGroups = [ 
      "wheel"
      "docker"
      "dialout"
      "tty"
      "uucp"
    ]; # Enable ‘sudo’ for the user.
    packages = with pkgs; [
      tree
    ];
    # Created using mkpasswd
    hashedPassword = "$6$CaCEWrNfJLit0lxA$ZUyRUZH9Vy6hlCseXfyRuz2KxYTtrAieGUqWRnpEnnJA3PdbJE8M.kmn6JKyMlYHRu7yNfvlM1F7oT7efwp7l.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFh6m4qX4U4sYAI+ngMuLACi4pqSz2pNjdPcB8aEzD6k"
    ];
  };

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = "/var/lib/rancher/k3s/server/token";
    extraFlags = toString ([
      "--write-kubeconfig-mode \"0644\""
      "--cluster-init"
      "--disable servicelb"
      "--disable traefik"
      "--disable local-storage"
      "--kubelet-arg=max-pods=150"
      "--kube-apiserver-arg=event-ttl=72h"
      "--etcd-arg=quota-backend-bytes=4294967296"
      "--etcd-arg=auto-compaction-mode=periodic"
      "--etcd-arg=auto-compaction-retention=24h"
      "--etcd-snapshot-schedule-cron=0 */6 * * *"
      "--etcd-snapshot-retention=28"
      "--etcd-snapshot-compress"
    ] ++ (if meta.hostname == "perun" then [] else [
      "--server https://perun:6443"
    ]));
    clusterInit = (meta.hostname == "perun");
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     vim
     cifs-utils
     nfs-utils
     git
  ];

  # List services that you want to enable:
  services.openssh.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ 80 ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a newer NixOS release.
  #
  # This value does NOT affect the Nixpkgs version your packages and OS are pulled from,
  # so changing it will NOT upgrade your system.
  #
  # This value being lower than the current NixOS release does NOT mean your system is
  # out of date, out of support, or vulnerable.
  #
  # Do NOT change this value unless you have manually inspected all the changes it would make to your configuration,
  # and migrated your data accordingly.
  #
  # For more information, see `man configuration.nix` or https://nixos.org/manual/nixos/stable/options#opt-system.stateVersion .
  system.stateVersion = "25.11"; # Did you read the comment?
}
