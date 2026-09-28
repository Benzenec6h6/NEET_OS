{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.limine;

  # ★ inieet.nix が system.build に登録したバイナリを参照
  limineInstall = config.system.build.limineInstall;

  liminePkg = cfg.package;

  # ブートローダのインストール・更新を行うスクリプト本体
  installBootloader = pkgs.writeShellScript "install-limine" ''
    set -euo pipefail

    BOOT_DIR="${cfg.bootDir}"
    LIMINE_PKG="${liminePkg}"
    export LIMINE_TIMEOUT="${toString cfg.timeout}"

    # 1. ディレクトリの存在確認
    if [ ! -d "$BOOT_DIR" ]; then
      echo "limine-install: error: boot directory '$BOOT_DIR' does not exist!" >&2
      exit 1
    fi

    # 2. 実機安全対策: /boot が独立パーティションとして正しくマウントされているか確認
    if ! ${pkgs.util-linux}/bin/mountpoint -q "$BOOT_DIR"; then
      echo "limine-install: error: target '$BOOT_DIR' is not a mountpoint!" >&2
      echo "limine-install: please ensure the EFI System Partition is mounted at $BOOT_DIR." >&2
      exit 1
    fi

    # 3. Rust 製の limine-install を実行
    exec ${limineInstall}/bin/limine-install "$BOOT_DIR" "$LIMINE_PKG"
  '';
in {
  options = {
    boot.loader.limine = {
      enable = lib.mkEnableOption "Limine bootloader for NEET OS";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.limine;
        description = "Limine package containing UEFI binaries.";
      };

      bootDir = lib.mkOption {
        type = lib.types.str;
        default = "/boot";
        description = "Mount point of the EFI System Partition (ESP).";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Timeout in seconds before booting the default entry.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # NixOS 互換のシステムフック
    system.build.installBootLoader = installBootloader;

    environment.systemPackages = [
      limineInstall

      # 既存の update-limine (互換用)
      (pkgs.writeScriptBin "update-limine" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')

      # ★ 抽象コマンド名 install-bootloader (rebuild.sh から呼べる共通名)
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];
  };
}
