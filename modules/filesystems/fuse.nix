{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.supportedFilesystems.fuse;
  cfgInitrd = config.boot.initrd.supportedFilesystems.fuse;
in {
  options = {
    # Stage 1 (initrd) 用の FUSE 設定
    boot.initrd.supportedFilesystems.fuse = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "initrd 内で fuse を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [];
        description = "initrd 内に含める fuse 関連パッケージ";
      };
    };

    # Stage 2 (実行時) 用の FUSE 設定
    boot.supportedFilesystems.fuse = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "システムで fuse を有効にするかどうか";
      };

      packages = lib.mkOption {
        type = with lib.types; listOf package;
        default = [pkgs.fuse3 pkgs.fuse];
        description = "システムに含める fuse 関連パッケージ";
      };
    };
  };

  config = lib.mkMerge [
    # ==============================================================
    # Stage 2 (実行時) の設定
    # ==============================================================
    (lib.mkIf cfg.enable {
      # 1. カーネルモジュールのロード
      boot.kernelModules = ["fuse"];

      # 2. ツール群 (mount.fuse3 等) を PATH に追加
      environment.systemPackages = cfg.packages;

      # 3. /run/wrappers/bin に setuid(root) で配置 (inieet の wrappers.rs 連携)
      neet.security.wrappers = {
        fusermount = {
          source = "${pkgs.fuse}/bin/fusermount";
          setuid = true;
          owner = "root";
          group = "root";
        };
        fusermount3 = {
          source = "${pkgs.fuse3}/bin/fusermount3";
          setuid = true;
          owner = "root";
          group = "root";
        };
      };

      # 4. デバイスマネージャへのルール登録 (mdevd & gardendevd の双方をサポート)
      services.mdevd.rules = ''
        -SUBSYSTEM=misc;fuse 0:0 0666
      '';

      services.udev.extraRules = ''
        KERNEL=="fuse", MODE="0666"
      '';

      # 5. rclone や仮想ファイルシステムで非 root ユーザーが -o allow_other を使うために必須
      environment.etc."fuse.conf".text = ''
        user_allow_other
      '';
    })

    # ==============================================================
    # Stage 1 (initrd) の設定
    # ==============================================================
    (lib.mkIf cfgInitrd.enable {
      boot.initrd.availableKernelModules = ["fuse"];
      boot.initrd.supportedFilesystems.fuse.packages = [pkgs.pkgsStatic.fuse3];

      # initrd でも mdevd にルールを注入 (Stage 1 では mdevd 固定)
      services.mdevd.rules = ''
        -SUBSYSTEM=misc;fuse 0:0 0666
      '';
    })
  ];
}
