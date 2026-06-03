{ lib, pkgs, meta, ... }:

let
  authorizedKeys = [
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFh6m4qX4U4sYAI+ngMuLACi4pqSz2pNjdPcB8aEzD6k"
  ];

  primaryUser = {
    isNormalUser = true;
    extraGroups = meta.userGroups;
    packages = with pkgs; [ tree ];
    openssh.authorizedKeys.keys = authorizedKeys;
  } // lib.optionalAttrs (meta ? hashedPassword) {
    hashedPassword = meta.hashedPassword;
  };
in {
  nix = {
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  boot.loader.systemd-boot.enable = true;
  boot.loader.systemd-boot.configurationLimit = 5;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = meta.hostname;
  networking.networkmanager.enable = true;
  networking.firewall.enable = meta.firewallEnable;
  networking.firewall.allowedTCPPorts = meta.firewallTCPPorts;

  time.timeZone = "Europe/Berlin";

  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
  };

  systemd.tmpfiles.rules = lib.mkIf meta.enableLonghornHostTweaks [
    "L+ /usr/local/bin - - - - /run/current-system/sw/bin/"
  ];

  virtualisation.docker.logDriver = lib.mkIf meta.enableLonghornHostTweaks "json-file";

  services.openiscsi = lib.mkIf meta.enableOpeniscsi {
    enable = true;
    name = "iqn.2016-04.com.open-iscsi:${meta.hostname}";
  };

  services.tailscale.enable = true;
  services.qemuGuest.enable = meta.enableQemuGuest;

  systemd.services.tailscale-public-tcp = lib.mkIf meta.enableTailscalePublicTcp {
    description = "Expose api-photos.def4alt.com and minecraft.def4alt.com over Tailscale";
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
          exit 0
        fi

        sleep 2
      done

      exit 1
    '';
  };

  users.users.${meta.primaryUser} = primaryUser;

  services.k3s = {
    enable = true;
    role = "server";
    tokenFile = "/var/lib/rancher/k3s/server/token";
    extraFlags = toString ([
      "--write-kubeconfig-mode \"0644\""
      "--cluster-init"
      "--disable servicelb"
      "--disable traefik"
      "--kubelet-arg=max-pods=150"
      "--kube-apiserver-arg=event-ttl=72h"
      "--etcd-arg=quota-backend-bytes=4294967296"
      "--etcd-arg=auto-compaction-mode=periodic"
      "--etcd-arg=auto-compaction-retention=24h"
      "--etcd-snapshot-schedule-cron=0 */6 * * *"
      "--etcd-snapshot-retention=28"
      "--etcd-snapshot-compress"
    ] ++ meta.k3sExtraFlags);
    clusterInit = true;
  };

  environment.systemPackages = with pkgs; [
    vim
    cifs-utils
    nfs-utils
    git
  ];

  services.openssh.enable = true;

  system.stateVersion = "25.11";
}
