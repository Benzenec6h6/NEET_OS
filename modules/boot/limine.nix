{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.limine;

  # inieet から Rust 製の limine-install バイナリを取得
  inherit (import ../system/etc/inieet {inherit pkgs lib;}) limineInstall;

  # Limine のパッケージ
  liminePkg = cfg.package;

  # ブートローダのインストール・更新を行うスクリプト
  installBootloader = pkgs.writeShellScript "install-limine" ''
    set -e
    BOOT_DIR="${cfg.bootDir}"
    LIMINE_PKG="${liminePkg}"

    if [ ! -d "$BOOT_DIR" ]; then
      echo "limine-install: error: boot directory '$BOOT_DIR' does not exist!" >&2
      exit 1
    fi

    # Rust 製の limine-install を実行
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
    # 成果物として installBootLoader を登録 (rebuild スクリプトやインストーラが呼ぶ)
    system.build.installBootLoader = installBootloader;

    # 手動実行やデバッグ用に環境にも入れておく
    environment.systemPackages = [
      limineInstall
      (pkgs.writeScriptBin "update-limine" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];
  };
}
