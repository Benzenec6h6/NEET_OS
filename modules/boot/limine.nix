{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.limine;

  # inieet から Rust 製の limine-install バイナリを取得
  inherit (import ../system/etc/inieet {inherit pkgs lib;}) limineInstall;

  liminePkg = cfg.package;

  # ブートローダのインストール・更新を行うスクリプト
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
    # (util-linux の mountpoint コマンドを使用)
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
    system.build.installBootLoader = installBootloader;

    environment.systemPackages = [
      limineInstall
      (pkgs.writeScriptBin "update-limine" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];
  };
}
