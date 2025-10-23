# Edit this configuration file to define what should be installed on
# your system. Help is available in the configuration.nix(5) man page, on
# https://search.nixos.org/options and in the NixOS manual (`nixos-help`).

{  pkgs, meta, ... }:

let
  dockerBin = "${pkgs.docker}/bin/docker";
  zigbee2mqttUser = "1000";
  zigbee2mqttGroup = "100";
  homeassistantUser = "0";
  homeassistantGroup = "0";
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      ./pihole-compose.nix
      ./paperless-compose.nix
      ./zigbee2mqtt-compose.nix
      ./homeassistant-compose.nix
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
  networking.networkmanager.enable = true;
  networking.networkmanager.dns = "none";
  networking.networkmanager.unmanaged = [ "interface-name:docker*" "interface-name:br-*" ];

  networking.nameservers = [ "127.0.0.1" ]; # Point host DNS to itself (Docker forwards to Pi-hole)

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";
  console = {
    font = "Lat2-Terminus16";
    keyMap = "us";
    #useXkbConfig = true; # use xkb.options in tty.
  };

  virtualisation.docker = {
    enable = true;
  };

  systemd.services.docker-create-network-proxy = {
    description = "Create Docker proxy network";
    after = [ "docker.service" ];
    requires = [ "docker.service" ];
    wantedBy = [ "multi-user.target" ];

    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = ''/etc/docker/create-proxy-network.sh'';
      User = "perun";
      Group = "docker";
    };
  };

  environment.etc."docker/create-proxy-network.sh" = {
    text = ''
    #!/bin/sh
    set -e

    if ! ${dockerBin} network inspect proxy >/dev/null 2>&1; then
      ${dockerBin} network create \
        --driver bridge \
        --subnet 172.20.0.0/16 \
        --gateway 172.20.0.1 \
        proxy
    fi
  '';
    mode = "0555";
  };

  # Add custom DNS via dnsmasq config
  environment.etc."dnsmasq.d/02-custom-dns.conf" = {
    text = ''
      address=/pihole.blokth.com/192.168.88.189
      address=/papers.blokth.com/192.168.88.189
      address=/home.blokth.com/192.168.88.189
      address=/zigbee.blokth.com/192.168.88.189
      address=/photos.blokth.com/192.168.88.189
    '';
    mode = "0444"; # Read-only for all
  };

  # Zigbee2MQTT configuration file managed by Nix
  environment.etc."zigbee2mqtt/configuration.yaml" = {
    text = ''
      homeassistant: true
      permit_join: true
      mqtt:
        base_topic: zigbee2mqtt
        server: 'mqtt://172.20.0.1'
        # user: my_user
        # password: my_password
      serial:
        port: /dev/ttyACM0
        adapter: ember
      frontend:
        port: 8080
      # devices:
      #   '0x123456789abcdef0':
      #     friendly_name: my_switch
      # advanced:
      #   log_level: info
    '';
    mode = "0644";
  };

  # Setup persistent data directory for Zigbee2MQTT
  systemd.tmpfiles.rules = [
    "d /var/lib/zigbee2mqtt ${zigbee2mqttUser} ${zigbee2mqttGroup} - -"
    "d /var/lib/homeassistant ${homeassistantUser} ${homeassistantGroup} - -"
  ];

  # Home Assistant configuration file managed by Nix
  environment.etc."homeassistant/configuration.yaml" = {
    text = ''
      # Includes common integrations (frontend, api, etc.)
      default_config:

      # Configure HTTP for Traefik reverse proxy
      http:
        use_x_forwarded_for: true
        trusted_proxies:
          - 192.168.88.189
          - 172.20.0.0/16  # Docker proxy network
          - 127.0.0.1

      script: !include scripts.yaml
      automation: !include automations.yaml
      scene: !include scenes.yaml
    '';
    mode = "0666"; # Read-write
  };

  environment.etc."homeassistant/scripts.yaml" = {
    text = ''
    light_sunrise:
      use_blueprint:
        path: steku/parabolic_alarm_script.yaml
      alias: Light Sunrise
      description: ""
    '';
    mode = "0666"; # Read-write
  };

  environment.etc."homeassistant/automations.yaml" = {
    text = ''
    - id: "1760777091385"
      alias: Sunlight Alarm
      description: ""
      use_blueprint:
        path: steku/parabolic_alarm.yaml
        input:
          alarm_start_time: input_datetime.wakeup
          offset_from_start_time: -00:30:00
          workday_sensor: binary_sensor.workday_sensor
          person_sensor: person.andrii_olkhovych
          alarm_script: script.light_sunrise
          target_light: light.0x001788010e1ba8c5
          post_action:
          - action: light.turn_on
            metadata: {}
            data:
              color_temp_kelvin: 6500
              brightness_pct: 100
            target:
              area_id: bedroom
    '';
    mode = "0666"; # Read-write
  };

  environment.etc."homeassistant/scenes.yaml" = {
    text = ''
    - id: '1761241547056'
      name: Wind Down
      entities:
        light.0x0c2a6ffffe45ba25:
          supported_color_modes:
          - onoff
          color_mode:
          friendly_name: stand lamp
          supported_features: 0
          state: 'off'
        light.0x001788010e1ba8c5:
          min_color_temp_kelvin: 2202
          max_color_temp_kelvin: 4504
          min_mireds: 222
          max_mireds: 454
          effect_list:
          - blink
          - breathe
          - okay
          - channel_change
          - candle
          - finish_effect
          - stop_effect
          - stop_hue_effect
          supported_color_modes:
          - color_temp
          effect:
          color_mode: color_temp
          brightness: 255
          color_temp_kelvin: 2202
          color_temp: 454
          hs_color:
          - 29.79
          - 84.553
          rgb_color:
          - 255
          - 146
          - 39
          xy_color:
          - 0.579
          - 0.388
          friendly_name: bed lamp
          supported_features: 44
          state: 'on'
        light.midesklamppro_b53c_mijia_desk_lamp_sw:
          min_color_temp_kelvin: 2500
          max_color_temp_kelvin: 20000
          min_mireds: 50
          max_mireds: 400
          supported_color_modes:
          - color_temp
          color_mode: color_temp
          brightness: 255
          color_temp_kelvin: 2500
          color_temp: 400
          hs_color:
          - 28.874
          - 72.522
          rgb_color:
          - 255
          - 159
          - 70
          xy_color:
          - 0.546
          - 0.389
          friendly_name: desk lamp
          supported_features: 0
          state: 'on'
      icon: mdi:bed
      metadata: {}
    '';
    mode = "0666"; # Read-write
  };

  services.traefik = {
    enable = true;

    staticConfigOptions = {
      entryPoints = {
        web = {
          address = ":80";
          # Define the redirect middleware for http
          http.redirections.entryPoint = {
            to = "websecure";
            scheme = "https";
            permanent = true;
          };
        };
        websecure = {
          address = ":443";
          http.tls = {}; # Enable basic TLS, Traefik generates default cert
        };
      };

      providers = {
        docker = {
          network = "proxy";
          exposedByDefault = false; # Only expose containers with traefik.enable=true label
        };
      };
    };

    dynamicConfigOptions = {
      http.routers = {
        homeassistant = {
          rule = "Host(`home.blokth.com`)";
          service = "homeassistant";
          entryPoints = ["websecure"];
          tls = {};
        };
      };
      http.services = {
        homeassistant.loadBalancer.servers = [
          { url = "http://192.168.88.189:8123"; }
        ];
      };
    };
  };

  services.mosquitto = {
    enable = true;
    listeners = [
      {
        acl = [ "pattern readwrite #" ];
        omitPasswordAuth = true;
        settings.allow_anonymous = true;
      }
    ];
  };

  users.groups.docker.members = [ "perun" "traefik" ];

  # Define a user account. Don't forget to set a password with 'passwd'.
  users.users.perun = {
    isNormalUser = true;
    extraGroups = [ 
      "wheel"
      "docker"
      "dialout"
      "tty"
      "uucp"
    ]; # Enable 'sudo' for the user.
    packages = with pkgs; [
      tree
    ];
    # Created using mkpasswd
    hashedPassword = "$6$CaCEWrNfJLit0lxA$ZUyRUZH9Vy6hlCseXfyRuz2KxYTtrAieGUqWRnpEnnJA3PdbJE8M.kmn6JKyMlYHRu7yNfvlM1F7oT7efwp7l.";
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFh6m4qX4U4sYAI+ngMuLACi4pqSz2pNjdPcB8aEzD6k"
    ];
  };

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
     vim
     dig
     git
  ];

  # List services that you want to enable:

  services.openssh.enable = true;

  # Allow and proxy mDNS on the host
  services.avahi = {
    enable = true;
    nssmdns4 = true;
    openFirewall = true;   # opens UDP 5353
    reflector = true;      # reflects between LAN and other ifaces (e.g., docker)
  };

  # Open ports in the firewall.
  networking.firewall.allowedTCPPorts = [ 
    80
    443
    53
    22
    1883
    21064
  ];
  networking.firewall.allowedUDPPorts = [ 
    53
    5353   # mDNS
    1900   # SSDP/UPnP (other discoveries)
    21064
  ];
  # Or disable the firewall altogether.
  networking.firewall.enable = true;
  
  # Copy the NixOS configuration file and link it from the resulting system
  # (/run/current-system/configuration.nix). This is useful in case you
  # accidentally delete configuration.nix.
  # system.copySystemConfiguration = true;

  # This option defines the first version of NixOS you have installed on this particular machine,
  # and is used to maintain compatibility with application data (e.g. databases) created on older NixOS versions.
  #
  # Most users should NEVER change this value after the initial install, for any reason,
  # even if you've upgraded your system to a new NixOS release.
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
  system.stateVersion = "25.05"; # Did you read the comment?

}
