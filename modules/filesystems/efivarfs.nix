{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.filesystems.efivarfs;
in {
  options.filesystems.efivarfs = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable efivarfs support and mount at /sys/firmware/efi/efivars";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Stage 1 (initrd) にモジュールを含めてロードさせる
    boot.initrd.availableKernelModules = ["efivarfs"];

    # 念のため Stage 2 (システム全体) でもロード対象に含めておく
    boot.kernelModules = ["efivarfs"];

    # 2. Stage 2 でのマウント定義 (defaults のみ)
    boot.virtualFileSystems."/sys/firmware/efi/efivars" = {
      device = "efivarfs";
      fsType = "efivarfs";
      options = ["defaults"];
    };
  };
}
