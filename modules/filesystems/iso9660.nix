{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    # Stage 1 (initrd) 用
    boot.initrd.supportedFilesystems.iso9660 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で ISO 9660 を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "initrd 内に含める ISO 関連パッケージ";
      };
    };

    # Stage 2 (実行時) 用
    boot.supportedFilesystems.iso9660 = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで ISO 9660 を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "システムに含める ISO 関連パッケージ";
      };
    };
  };

  config = lib.mkMerge [
    # Stage 2
    (lib.mkIf config.boot.supportedFilesystems.iso9660.enable {
      boot.kernelModules = ["isofs"];
    })

    # Stage 1 (initrd)
    (lib.mkIf config.boot.initrd.supportedFilesystems.iso9660.enable {
      # ※ カーネルモジュール名は "iso9660" ではなく "isofs"
      boot.initrd.availableKernelModules = ["isofs"];
    })
  ];
}
