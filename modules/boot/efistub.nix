{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.efistub;
  espSync = config.system.build.espSync;
  efistubSync = config.system.build.efistubSync;

  # パイプライン: ESP の成果物配置・GC -> NVRAM の同期・GC
  installBootloader = pkgs.writeShellScript "install-efistub" ''
    set -euo pipefail

    echo "==> [install-efistub] 1/2: Synchronizing payloads to ESP..."
    ${espSync}/bin/esp-sync "${cfg.bootDir}"

    echo "==> [install-efistub] 2/2: Synchronizing UEFI NVRAM entries..."
    exec ${efistubSync}/bin/efistub-sync \
      "${cfg.bootDir}" "${cfg.efiDisk}" "${toString cfg.efiPartition}"
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
      default = "";
      description = "ESP が存在するディスクデバイス名 (空の場合は自動検出)";
    };

    efiPartition = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "ESP のパーティション番号 (efiDisk を手動指定した場合のみ使用)";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.efibootmgr
      espSync
      efistubSync
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];

    system.build.installBootLoader = installBootloader;
  };
}
