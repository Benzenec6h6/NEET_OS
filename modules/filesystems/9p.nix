{
  config,
  lib,
  ...
}: {
  options = {
    boot.initrd.supportedFilesystems."9p" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable support for the `9p` filesystem in the initial ramdisk.
        '';
      };
    };

    boot.supportedFilesystems."9p" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Whether to enable support for the `9p` filesystem.
        '';
      };
    };
  };

  config = {
    # 9p の Stage 2 側モジュール
    boot.kernelModules = lib.mkIf config.boot.supportedFilesystems."9p".enable [
      "9p"
      "9pnet_virtio"
    ];

    # 9p の Stage 1 (initrd) 側モジュール
    boot.initrd.availableKernelModules = lib.mkIf config.boot.initrd.supportedFilesystems."9p".enable [
      "9p"
      "9pnet_virtio"
      "virtio_pci"
      "virtio_net"
      "virtio_blk"
      "virtio_mmio"
    ];
  };
}
