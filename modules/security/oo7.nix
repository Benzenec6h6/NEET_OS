{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.security.oo7;
in {
  options.neet.security.oo7 = {
    enable = mkEnableOption "oo7 Secret Service provider and PAM integration";

    serverPackage = mkOption {
      type = types.package;
      default = pkgs.oo7-server;
      description = "The package providing oo7-daemon.";
    };

    pamPackage = mkOption {
      type = types.package;
      default = pkgs.oo7-pam;
      description = "The package providing pam_oo7.so.";
    };

    portalPackage = mkOption {
      type = types.package;
      default = pkgs.oo7-portal;
      description = "The package providing oo7-portal.";
    };

    enablePortal = mkOption {
      type = types.bool;
      default = config.xdg.portal.enable;
      description = "Whether to register oo7-portal with xdg-desktop-portal.";
    };
  };

  config = mkIf cfg.enable {
    # 1. パッケージと D-Bus サービスの登録 (D-Bus activation 対応)
    environment.systemPackages =
      [
        cfg.serverPackage
        cfg.pamPackage
        pkgs.libsecret # 動作検証用の secret-tool コマンド
      ]
      ++ optional (pkgs ? oo7-cli) pkgs.oo7-cli;

    services.dbus.packages = [cfg.serverPackage];

    # 2. XDG Desktop Portal 連携 (Flatpak 等の Secret Portal)
    xdg.portal = mkIf cfg.enablePortal {
      portals = [cfg.portalPackage];
      config = {
        common = {
          extraRules = {
            "org.freedesktop.impl.portal.Secret" = ["oo7"];
          };
        };
      };
    };

    # 3. 各ログインユーザーの s6-rc に oo7 サービスを自動配備
    # user-session.sh で DBUS_SESSION_BUS_ADDRESS が export された状態で起動する
    system.s6-rc.users =
      mapAttrs (_name: _u: {
        services.oo7 = {
          type = "longrun";
          dependencies = ["dbus"];
          autoStart = true;
          run = ''
            #!/bin/sh
            exec ${cfg.serverPackage}/bin/oo7-daemon
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
