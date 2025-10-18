# Auto-generated using compose2nix v0.3.3-pre.
{ pkgs, lib, ... }:

{
  # Runtime
  virtualisation.docker = {
    enable = true;
    autoPrune.enable = true;
  };
  virtualisation.oci-containers.backend = "docker";

  # Containers
  virtualisation.oci-containers.containers."paperless-broker" = {
    image = "redis:8";
    volumes = [
      "paperless_redisdata:/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=broker"
      "--network=paperless_paperless_internal"
    ];
  };
  systemd.services."docker-paperless-broker" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_redisdata.service"
    ];
    requires = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_redisdata.service"
    ];
    partOf = [
      "docker-compose-paperless-root.target"
    ];
    wantedBy = [
      "docker-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-db" = {
    image = "postgres:17";
    environment = {
      "POSTGRES_DB" = "paperless";
      "POSTGRES_PASSWORD" = "changeme";
      "POSTGRES_USER" = "paperless";
    };
    volumes = [
      "paperless_postgres_data:/var/lib/postgresql/data:rw"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=db"
      "--network=paperless_paperless_internal"
    ];
  };
  systemd.services."docker-paperless-db" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_postgres_data.service"
    ];
    requires = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_postgres_data.service"
    ];
    partOf = [
      "docker-compose-paperless-root.target"
    ];
    wantedBy = [
      "docker-compose-paperless-root.target"
    ];
  };
  virtualisation.oci-containers.containers."paperless-webserver" = {
    image = "ghcr.io/paperless-ngx/paperless-ngx:latest";
    environment = {
      "PAPERLESS_DBENGINE" = "postgresql";
      "PAPERLESS_DBHOST" = "db";
      "PAPERLESS_DBNAME" = "paperless";
      "PAPERLESS_DBPASS" = "changeme";
      "PAPERLESS_DBPORT" = "5432";
      "PAPERLESS_DBUSER" = "paperless";
      "PAPERLESS_REDIS" = "redis://broker:6379";
      "PAPERLESS_SECRET_KEY" = "changeme";
      "PAPERLESS_TIME_ZONE" = "Europe/Berlin";
      "PAPERLESS_URL" = "https://papers.blokth.com";
    };
    volumes = [
      "paperless_consume:/usr/src/paperless/consume:rw"
      "paperless_data:/usr/src/paperless/data:rw"
      "paperless_export:/usr/src/paperless/export:rw"
      "paperless_media:/usr/src/paperless/media:rw"
    ];
    labels = {
      "traefik.enable" = "true";
      "traefik.http.routers.paperless-secure.entrypoints" = "websecure";
      "traefik.http.routers.paperless-secure.rule" = "Host(`papers.blokth.com`)";
      "traefik.http.routers.paperless-secure.service" = "paperless-service";
      "traefik.http.routers.paperless-secure.tls" = "true";
      "traefik.http.services.paperless-service.loadbalancer.server.port" = "8000";
    };
    dependsOn = [
      "paperless-broker"
      "paperless-db"
    ];
    log-driver = "journald";
    extraOptions = [
      "--network-alias=webserver"
      "--network=paperless_paperless_internal"
      "--network=proxy"
    ];
  };
  systemd.services."docker-paperless-webserver" = {
    serviceConfig = {
      Restart = lib.mkOverride 90 "always";
      RestartMaxDelaySec = lib.mkOverride 90 "1m";
      RestartSec = lib.mkOverride 90 "100ms";
      RestartSteps = lib.mkOverride 90 9;
    };
    after = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_consume.service"
      "docker-volume-paperless_data.service"
      "docker-volume-paperless_export.service"
      "docker-volume-paperless_media.service"
    ];
    requires = [
      "docker-network-paperless_paperless_internal.service"
      "docker-volume-paperless_consume.service"
      "docker-volume-paperless_data.service"
      "docker-volume-paperless_export.service"
      "docker-volume-paperless_media.service"
    ];
    partOf = [
      "docker-compose-paperless-root.target"
    ];
    wantedBy = [
      "docker-compose-paperless-root.target"
    ];
  };

  # Networks
  systemd.services."docker-network-paperless_paperless_internal" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStop = "docker network rm -f paperless_paperless_internal";
    };
    script = ''
      docker network inspect paperless_paperless_internal || docker network create paperless_paperless_internal --driver=bridge
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };

  # Volumes
  systemd.services."docker-volume-paperless_consume" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_consume || docker volume create paperless_consume
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };
  systemd.services."docker-volume-paperless_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_data || docker volume create paperless_data
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };
  systemd.services."docker-volume-paperless_export" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_export || docker volume create paperless_export
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };
  systemd.services."docker-volume-paperless_media" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_media || docker volume create paperless_media
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };
  systemd.services."docker-volume-paperless_postgres_data" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_postgres_data || docker volume create paperless_postgres_data
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };
  systemd.services."docker-volume-paperless_redisdata" = {
    path = [ pkgs.docker ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      docker volume inspect paperless_redisdata || docker volume create paperless_redisdata
    '';
    partOf = [ "docker-compose-paperless-root.target" ];
    wantedBy = [ "docker-compose-paperless-root.target" ];
  };

  # Root service
  # When started, this will automatically create all resources and start
  # the containers. When stopped, this will teardown all resources.
  systemd.targets."docker-compose-paperless-root" = {
    unitConfig = {
      Description = "Root target generated by compose2nix.";
    };
    wantedBy = [ "multi-user.target" ];
  };
}
