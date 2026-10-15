{
  config,
  lib,
  ...
}: let
  cfg = config.boot.supportedFilesystems.overlay;
  cfgInitrd = config.boot.initrd.supportedFilesystems.overlay;
in {
  options = {
    # Stage 1 (initrd) で OverlayFS を使う場合 (Live USB 等の作成で将来役立ちます)
    boot.initrd.supportedFilesystems.overlay = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で overlay ファイルシステムを有効にするかどうか";
      };
    };

    # Stage 2 (実行時) で OverlayFS を使う場合
    boot.supportedFilesystems.overlay = {
      enable = lib.mkOption {
        type = lib.types.bool;
        # rebuild test などで手動マウントするため、標準で有効にしておくと便利です
        default = true;
        description = "システムで overlay ファイルシステムを有効にするかどうか";
      };
    };
  };

  config = lib.mkMerge [
    # Stage 2: overlay.ko をロード
    (lib.mkIf cfg.enable {
      boot.kernelModules = ["overlay"];
    })

    # Stage 1: initrd に overlay.ko を含める
    (lib.mkIf cfgInitrd.enable {
      boot.initrd.availableKernelModules = ["overlay"];
    })
  ];
}
