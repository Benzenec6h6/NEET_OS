{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    # Stage 1 (initrd) 用の Btrfs 設定
    boot.initrd.supportedFilesystems.btrfs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で btrfs を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "initrd 内に含める btrfs 関連パッケージ";
      };
    };

    # Stage 2 (実行時) 用の Btrfs 設定
    boot.supportedFilesystems.btrfs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで btrfs を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "システムに含める btrfs 関連パッケージ";
      };
    };
  };

  config = lib.mkMerge [
    # --- Stage 2 側の有効化 ---
    (lib.mkIf config.boot.supportedFilesystems.btrfs.enable {
      boot.kernelModules = ["btrfs"];
      # システム全体で使うツール
      boot.supportedFilesystems.btrfs.packages = [pkgs.btrfs-progs];
    })

    # --- Stage 1 (initrd) 側の有効化 ---
    (lib.mkIf config.boot.initrd.supportedFilesystems.btrfs.enable {
      # Btrfs のマウントに必要なカーネルモジュール群
      boot.initrd.availableKernelModules = [
        "btrfs"
        "crc32c" # チェックサム用
        "xxhash64" # 新しいBtrfsで使われる
        "sha256" # 基本的なハッシュ
        "blake2b-256" # 最新のBtrfs用
      ];

      # 静的バイナリの方が initrd には優しい
      boot.initrd.supportedFilesystems.btrfs.packages = [pkgs.pkgsStatic.btrfs-progs];
    })
  ];
}
