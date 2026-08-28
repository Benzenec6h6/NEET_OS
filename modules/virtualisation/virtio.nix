{
  config,
  lib,
  ...
}: {
  options.virtualisation.virtio = {
    enable = lib.mkEnableOption "VirtIO guest drivers";

    initrd.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable VirtIO drivers in stage 1 initrd for boot.";
    };
  };

  config = lib.mkIf config.virtualisation.virtio.enable {
    # Stage 2 用
    boot.kernelModules = [
      "virtio_pci"
      "virtio_balloon"
    ];

    # Stage 1 (initrd) 用
    # 注意: バス/ブロックデバイスドライバを確実に高位モジュールより前に読み込ませるため順序に留意
    boot.initrd.availableKernelModules = lib.mkIf config.virtualisation.virtio.initrd.enable [
      "virtio_pci"
      "virtio_mmio"
      "virtio_blk"
      "virtio_scsi"
      "virtio_net"
    ];
  };
}
