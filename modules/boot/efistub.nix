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

    BOOT_DIR="${cfg.bootDir}"
    EFI_DISK="${cfg.efiDisk}"
    EFI_PART="${toString cfg.efiPartition}"

    # efiDisk が指定されていない場合は自動検出
    if [ -z "$EFI_DISK" ]; then
      echo "efistub: auto-detecting ESP device for $BOOT_DIR..."
      BOOT_DEV="$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE "$BOOT_DIR")"
      REAL_DEV="$(realpath "$BOOT_DEV")"

      EFI_DISK="/dev/$(${pkgs.util-linux}/bin/lsblk -no PKNAME "$REAL_DEV")"
      EFI_PART="$(${pkgs.util-linux}/bin/lsblk -no PARTN "$REAL_DEV")"

      echo "efistub: detected disk: $EFI_DISK, partition: $EFI_PART"
    fi

    exec ${efistubInstall}/bin/efistub-install "$BOOT_DIR" "$EFI_DISK" "$EFI_PART"
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
    # ★ efivarfs のマウント定義は filesystems/efivarfs.nix が担当するため削除

    # 依存パッケージと共通コマンドの提供
    environment.systemPackages = [
      pkgs.efibootmgr
      pkgs.util-linux
      efistubInstall
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];

    system.build.installBootLoader = installBootloader;
  };
}
