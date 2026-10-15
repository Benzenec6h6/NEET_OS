{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.supportedFilesystems."fuse.mergerfs";
  cfgInitrd = config.boot.initrd.supportedFilesystems."fuse.mergerfs";
in {
  options = {
    boot.initrd.supportedFilesystems."fuse.mergerfs" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で mergerfs を有効にするかどうか";
      };
      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [pkgs.pkgsStatic.mergerfs];
      };
    };

    boot.supportedFilesystems."fuse.mergerfs" = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで mergerfs を有効にするかどうか";
      };
      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [pkgs.mergerfs];
      };
    };
  };

  config = lib.mkMerge [
    (lib.mkIf cfg.enable {
      # mergerfs を使うなら必然的に fuse も有効化
      boot.supportedFilesystems.fuse.enable = true;
      environment.systemPackages = cfg.packages;
    })

    (lib.mkIf cfgInitrd.enable {
      boot.initrd.supportedFilesystems.fuse.enable = true;
      boot.initrd.supportedFilesystems."fuse.mergerfs".packages = cfgInitrd.packages;
    })
  ];
}
