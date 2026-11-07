{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.xdg.portal;

  # portals.conf 用のサブモジュール定義
  portalConfigOpts = {
    options = {
      default = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["hyprland" "gtk"];
        description = "デフォルトで使用するポータルバックエンドの優先順位リスト";
      };

      extraRules = mkOption {
        type = types.attrsOf (types.listOf types.str);
        default = {};
        example = {
          "org.freedesktop.impl.portal.ScreenCast" = ["hyprland"];
        };
        description = "特定の D-Bus インターフェースに対する個別バックエンド優先順位";
      };
    };
  };
in {
  options.xdg.portal = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable XDG desktop portals.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.xdg-desktop-portal;
      description = "The package to use for `xdg-desktop-portal`.";
    };

    portals = mkOption {
      type = with types; listOf package;
      default = [];
      description = "List of XDG desktop portal packages to install.";
    };

    # ★ 任意のデスクトップ環境から自己申告できる設定マップ
    config = mkOption {
      type = types.attrsOf (types.submodule portalConfigOpts);
      default = {};
      example = literalExpression ''
        {
          hyprland.default = [ "hyprland" "gtk" ];
          sway.default = [ "wlr" "gtk" ];
        }
      '';
      description = ''
        デスクトップ環境ごとの portals.conf 設定マップ。
        キー名がそのまま `<name>-portals.conf` のファイル名になります。
      '';
    };
  };

  config = mkIf cfg.enable {
    boot.supportedFilesystems.fuse.enable = mkDefault true;
    services.dbus.packages = [cfg.package] ++ cfg.portals;
    environment.systemPackages = [cfg.package] ++ cfg.portals;

    environment.pathsToLink = [
      "/share/xdg-desktop-portal"
      "/share/applications"
      "/share/dbus-1"
    ];

    # ★ cfg.config に宣言された設定から自動で /etc/xdg/xdg-desktop-portal/<desktop>-portals.conf を生成
    environment.etc =
      mapAttrs' (
        desktop: conf: let
          lines =
            ["[preferred]"]
            ++ optional (conf.default != []) "default=${concatStringsSep ";" conf.default}"
            ++ mapAttrsToList (k: v: "${k}=${concatStringsSep ";" v}") conf.extraRules;
        in
          nameValuePair "xdg/xdg-desktop-portal/${desktop}-portals.conf" {
            text = concatStringsSep "\n" lines + "\n";
          }
      )
      cfg.config;
  };
}
