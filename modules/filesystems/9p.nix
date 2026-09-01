{
  config,
  lib,
  ...
}: {
  options = {
    boot.initrd.supportedFilesystems."9p" = {
      enable = lib.mkEnableOption "9p filesystem support in initrd";
    };

    boot.supportedFilesystems."9p" = {
      enable = lib.mkEnableOption "9p filesystem support";
    };
  };

  config = {
    # Stage 2 側
    boot.kernelModules = lib.mkIf config.boot.supportedFilesystems."9p".enable (
      ["9p" "9pnet"]
      ++ lib.optional (config.virtualisation.virtio.enable or false) "9pnet_virtio"
    );

    # Stage 1 (initrd) 側
    boot.initrd.availableKernelModules = lib.mkIf config.boot.initrd.supportedFilesystems."9p".enable (
      ["9p" "9pnet"]
      ++ lib.optional (config.virtualisation.virtio.enable or false) "9pnet_virtio"
    );
  };
}
