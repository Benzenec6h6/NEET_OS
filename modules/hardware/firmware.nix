{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.hardware;
in {
  options = {
    hardware.enableDesktopFirmware = lib.mkOption {
      type = lib.types.bool;
      default = true; # デスクトップOSなのでデフォルトで有効化
      description = ''
        デスクトップ/ノートPCに必要な主要ファームウェアを一括で有効化します。
        (linux-firmware, sof-firmware, alsa-firmware, wireless-regdb)
      '';
    };

    hardware.enableAllFirmware = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        再配布制限のあるプロプライエタリなファームウェア (Broadcom Wi-Fi等) も含めて有効化します。
      '';
    };

    hardware.firmware = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = ''
        カーネルが要求した際に自動ロードされるファームウェアパッケージのリスト。
      '';
      apply = list:
        pkgs.buildEnv {
          name = "firmware";
          paths = list;
          pathsToLink = ["/lib/firmware"];
          ignoreCollisions = true;
        };
    };
  };

  config = lib.mkMerge [
    # 1. 一般的なデスクトップ環境向けファームウェア
    (lib.mkIf cfg.enableDesktopFirmware {
      hardware.firmware = with pkgs; [
        linux-firmware # GPU (AMD/Intel/Nouveau), Wi-Fi, Bluetooth
        sof-firmware # 第10世代以降のIntel/AMDノートPCのサウンド(Sound Open Firmware)
        alsa-firmware # レガシー/一部のサウンドカード
        wireless-regdb # Wi-Fiの電波規制DB (5GHz帯等の解放に必須)
      ];
    })

    # 2. 完全プロプライエタリ/特定チップ用ファームウェア
    (lib.mkIf cfg.enableAllFirmware {
      hardware.firmware = with pkgs; [
        broadcom-bt-firmware
        b43Firmware_5_1_138
        b43Firmware_6_30_163_46
      ];
    })
  ];
}
