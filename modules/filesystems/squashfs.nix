{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    # Stage 1 (initrd) 用
    boot.initrd.supportedFilesystems.squashfs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で SquashFS を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "initrd 内に含める SquashFS 関連パッケージ";
      };
    };

    # Stage 2 (実行時) 用
    boot.supportedFilesystems.squashfs = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで SquashFS を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "システムに含める SquashFS 関連パッケージ";
      };
    };
  };

  config = lib.mkMerge [
    # Stage 2
    (lib.mkIf config.boot.supportedFilesystems.squashfs.enable {
      boot.kernelModules = ["squashfs" "loop"];
      boot.supportedFilesystems.squashfs.packages = [pkgs.squashfs-tools];
    })

    # Stage 1 (initrd)
    (lib.mkIf config.boot.initrd.supportedFilesystems.squashfs.enable {
      boot.initrd.availableKernelModules = [
        "squashfs"
        "loop" # ISO内のsquashfsファイルをループマウントするのに必須
      ];
      # 必要に応じて静的バイナリ（unsquashfs などでトラブルシュートする場合）
      boot.initrd.supportedFilesystems.squashfs.packages = [pkgs.pkgsStatic.squashfs-tools];
    })
  ];
}
