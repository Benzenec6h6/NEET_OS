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
      # ★ efistub 等、UEFI 変数を必要とするローダが有効なら自動的に true
      default = config.boot.loader.efistub.enable or false;
      description = "Enable efivarfs support and mount at /sys/firmware/efi/efivars";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Stage 1 でドライバを先回りロード
    boot.initrd.kernelModules = ["efivarfs"];

    # 2. Stage 2 でのマウント定義 (nofail を排除したクリーンな設定)
    boot.virtualFileSystems."/sys/firmware/efi/efivars" = {
      device = "efivarfs";
      fsType = "efivarfs";
      options = ["defaults"];
    };
  };
}
