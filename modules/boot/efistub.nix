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

    # ★ efiDisk が指定されていない（空の）場合、マウント先から自動検出する
    if [ -z "$EFI_DISK" ]; then
      echo "efistub: auto-detecting ESP device for $BOOT_DIR..."
      # /boot をマウントしているデバイスノードを取得 (例: /dev/vda1, /dev/nvme0n1p1)
      BOOT_DEV="$(${pkgs.util-linux}/bin/findmnt -n -o SOURCE "$BOOT_DIR")"

      # 親ディスク名 (例: /dev/vda, /dev/nvme0n1)
      EFI_DISK="/dev/$(${pkgs.util-linux}/bin/lsblk -no PKNAME "$BOOT_DEV")"
      # パーティション番号 (例: 1)
      EFI_PART="$(${pkgs.util-linux}/bin/lsblk -no PARTN "$BOOT_DEV")"

      echo "efistub: detected disk: $EFI_DISK, partition: $EFI_PART"
    fi

    # efistub-install を実行
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
      default = ""; # ★ デフォルトを空文字にして自動検出を基本にする
      description = "ESP が存在するディスクデバイス名 (空の場合は自動検出)";
    };

    efiPartition = lib.mkOption {
      type = lib.types.int;
      default = 1;
      description = "ESP のパーティション番号 (efiDisk を手動指定した場合のみ使用)";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. efivarfs の自動マウント
    # ★ "nofail" を外し "defaults" のみにすることで、init-core がエラーなくマウントできるようになる
    boot.virtualFileSystems."/sys/firmware/efi/efivars" = {
      device = "efivarfs";
      fsType = "efivarfs";
      options = ["defaults"];
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
