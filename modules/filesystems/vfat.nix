{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    # Stage 1 (initrd) 用の vfat 設定
    boot.initrd.supportedFilesystems.vfat = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で vfat (FAT32) を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "initrd 内に含める vfat 関連パッケージ";
      };
    };

    # Stage 2 (実行時) 用の vfat 設定
    boot.supportedFilesystems.vfat = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで vfat (FAT32) を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "システムに含める vfat 関連パッケージ (dosfstools 等)";
      };
    };
  };

  config = lib.mkMerge [
    # --- Stage 2 (実行時) 側の有効化 ---
    (lib.mkIf config.boot.supportedFilesystems.vfat.enable {
      # FAT のファイル名処理には nls_cp437 等のコードページモジュールが必須
      boot.kernelModules = [
        "vfat"
        "fat"
        "nls_cp437"
        "nls_iso8859_1"
      ];
      # mkfs.vfat, fsck.vfat などの操作ツール
      boot.supportedFilesystems.vfat.packages = [pkgs.dosfstools];
    })

    # --- Stage 1 (initrd) 側の有効化 ---
    (lib.mkIf config.boot.initrd.supportedFilesystems.vfat.enable {
      boot.initrd.availableKernelModules = [
        "vfat"
        "fat"
        "nls_cp437"
        "nls_iso8859_1"
      ];
      boot.initrd.supportedFilesystems.vfat.packages = [pkgs.pkgsStatic.dosfstools];
    })
  ];
}
