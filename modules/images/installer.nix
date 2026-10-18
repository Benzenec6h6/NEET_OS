{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.installer;
in {
  options.installer = {
    enable = lib.mkEnableOption "NEET OS live installer environment";
  };

  config = lib.mkIf cfg.enable {
    # 1. img.zst ビルダーを自動有効化
    images.zst.enable = lib.mkDefault true;

    # 2. ブートローダのデフォルト (UEFI Limine)
    boot.loader.limine.enable = lib.mkDefault true;

    # 3. disks モジュールによる固定ディスクマウントを無効化
    disks.devices = lib.mkForce {};

    # 4. Live 環境用のファイルシステム構成 (init-core がこれをそのまま解釈)
    boot.fileSystems = {
      # 足場 A: RAM 上に tmpfs を用意 (Overlay の書き込みレイヤ用)
      "/run/live/overlay" = {
        device = "tmpfs";
        fsType = "tmpfs";
        options = ["mode=0755"];
        neededForBoot = true;
        initrdOnly = true; # Stage 1 内の足場としてマウント
      };

      # 足場 B: USB 内の SquashFS パーティションを RO マウント
      "/run/live/squashfs" = {
        device = "PARTLABEL=NEET_LIVE";
        fsType = "squashfs";
        options = ["ro"];
        neededForBoot = true;
        initrdOnly = true; # Stage 1 内の足場としてマウント
      };

      # ルート (/): tmpfs と SquashFS を OverlayFS で結合して /mnt にマウント
      "/" = {
        device = "overlay";
        fsType = "overlay";
        options = [
          "lowerdir=/run/live/squashfs"
          "upperdir=/run/live/overlay/upper"
          "workdir=/run/live/overlay/work"
        ];
        neededForBoot = true;
        # 足場がマウントされた後に / をマウントするように順序制御
        requires = [
          "/run/live/overlay"
          "/run/live/squashfs"
        ];
      };

      # EFI システムパーティション (Stage 2 で /boot にマウント)
      "/boot" = {
        device = "PARTLABEL=NEET_BOOT";
        fsType = "vfat";
        options = ["defaults" "umask=0077"];
        neededForBoot = false;
      };
    };

    # 5. インストール・暗号化・検証に必要なツール類
    environment.systemPackages = with pkgs; [
      cryptsetup
      gptfdisk
      parted
      util-linux
      dosfstools
      e2fsprogs
      btrfs-progs
      squashfs-tools

      git
      curl

      sbctl
      efibootmgr
    ];

    # 6. initrd に最低限必要なストレージ/USBドライバ
    boot.initrd.availableKernelModules = [
      "virtio_pci"
      "virtio_blk"
      "virtio_scsi"
      "usb_storage"
      "uas"
      "nvme"
      "ahci"
    ];
  };
}
