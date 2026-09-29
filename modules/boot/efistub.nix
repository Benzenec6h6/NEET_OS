{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.efistub;
  efistubInstall = config.system.build.efistubInstall;

  # シェル側の複雑な判定はすべて撤廃し、Rust バイナリに委ねる
  installBootloader = pkgs.writeShellScript "install-efistub" ''
    set -euo pipefail
    exec ${efistubInstall}/bin/efistub-install \
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
      default = ""; # 空なら Rust 側で自動検出
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
      efistubInstall
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];

    system.build.installBootLoader = installBootloader;
  };
}
