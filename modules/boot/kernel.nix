{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    boot.kernelPackages = lib.mkOption {
      default = pkgs.linuxPackages;
      defaultText = lib.literalExpression "pkgs.linuxPackages";
      type = lib.types.raw;
      description = "使用するカーネルパッケージ（標準は最新のLTSなど）";
    };

    boot.kernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "カーネルパラメータ";
    };

    boot.kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Stage 2 で自動ロードするモジュール";
    };

    system.modulesTree = lib.mkOption {
      type = lib.types.path;
      internal = true;
    };
  };

  config = {
    # カーネル本体と追加モジュールを1つのツリーにまとめる
    system.modulesTree = pkgs.aggregateModules [
      (lib.getOutput "modules" config.boot.kernelPackages.kernel)
    ];

    # デフォルトのカーネルパラメータ（シリアルコンソール等）
    boot.kernelParams = lib.mkDefault [
      "console=ttyS0"
      "panic=10"
    ];

    # 標準でロードしておくべきモジュール
    boot.kernelModules = lib.mkDefault ["loop" "atkbd"];

    boot.initrd.availableKernelModules =
      [
        # SATA/PATA
        "ahci"
        "sata_nv"
        "sata_via"
        "sata_sis"
        "sata_uli"
        "ata_piix"
        "pata_marvell"

        # NVMe
        "nvme"

        # SCSI（SATAディスクやUSBストレージの認識に必須）
        "sd_mod"
        "sr_mod"

        # SDカード / eMMC
        "mmc_block"

        # USB ホストコントローラ（USB 1.1 / 2.0 / 3.x）
        "uhci_hcd"
        "ehci_hcd"
        "ehci_pci"
        "ohci_hcd"
        "ohci_pci"
        "xhci_hcd"
        "xhci_pci"

        # キーボード・入力デバイス
        "usbhid"
        "hid_generic"
        "hid_lenovo"
        "hid_apple"
        "hid_roccat"
        "hid_logitech_hidpp"
        "hid_logitech_dj"
        "hid_microsoft"
        "hid_cherry"
        "hid_corsair"
      ]
      ++ lib.optionals pkgs.stdenv.hostPlatform.isx86 [
        # x86 のキーボード / RTC
        "pcips2"
        "atkbd"
        "i8042"
        "rtc_cmos"
      ];
  };
}
