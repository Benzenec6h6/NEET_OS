{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.efistub;
  efistubInstall = config.system.build.efistubInstall;

  installBootloader = pkgs.writeShellScript "install-efistub" ''
    set -euo pipefail

    # efivarfs がマウントされているか確認
    if [ ! -d "/sys/firmware/efi/efivars" ] || [ -z "$(ls -A /sys/firmware/efi/efivars 2>/dev/null)" ]; then
      echo "efistub: error: efivarfs is not mounted at /sys/firmware/efi/efivars!" >&2
      exit 1
    fi

    # efistub-install を実行
    exec ${efistubInstall}/bin/efistub-install "${cfg.bootDir}" "${cfg.efiDisk}" "${toString cfg.efiPartition}"
  '';
in {
  options.boot.loader.efistub = {
    enable = lib.mkEnableOption "EFISTUB direct bootloader for NEET OS";

    bootDir = lib.mkOption {
      type = lib.types.str;
      default = "/boot";
      description = "ESP のマウント先";
    };

    efiDisk = lib.mkOption {
      type = lib.types.str;
      default = "/dev/nvme0n1";
      description = "ESP が存在するディスクデバイス名";
    };

    efiPartition = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "ESP のパーティション番号 (例: 1)";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. efivarfs の自動マウント
    fileSystems."/sys/firmware/efi/efivars" = {
      device = "efivarfs";
      fsType = "efivarfs";
      options = ["defaults" "nofail"];
    };

    # 2. 依存パッケージと共通コマンドの提供
    environment.systemPackages = [
      pkgs.efibootmgr
      efistubInstall
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];

    system.build.installBootLoader = installBootloader;
  };
}
