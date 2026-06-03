{
  disko.devices = {
    disk = {
      main = {
        type = "disk";
        # Verified from the 2026-06-03 Hetzner rescue environment on 46.62.137.102.
        device = "/dev/disk/by-id/scsi-0QEMU_QEMU_HARDDISK_119416279";
        content = {
          type = "gpt";
          partitions = {
            ESP = {
              priority = 1;
              name = "ESP";
              start = "1M";
              end = "1G";
              type = "EF00";
              content = {
                type = "filesystem";
                format = "vfat";
                mountpoint = "/boot";
              };
            };
            root = {
              size = "100%";
              content = {
                type = "btrfs";
                extraArgs = [ "-f" ];
                subvolumes = {
                  "/rootfs" = {
                    mountpoint = "/";
                  };
                  "/home" = {
                    mountOptions = [ "compress=zstd" ];
                    mountpoint = "/home";
                  };
                  "/nix" = {
                    mountOptions = [ "compress=zstd" "noatime" ];
                    mountpoint = "/nix";
                  };
                  "/var/lib/rancher" = {
                    mountOptions = [ "compress=zstd" "noatime" ];
                    mountpoint = "/var/lib/rancher";
                  };
                };
                mountpoint = "/partition-root";
              };
            };
          };
        };
      };
    };
  };
}
