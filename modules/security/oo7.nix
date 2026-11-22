{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.security.oo7;

  daemonBin =
    if cfg.useWrapper
    then "/run/wrappers/bin/oo7-daemon"
    else "${cfg.serverPackage}/libexec/oo7-daemon";
in {
  options = {
    neet.security.oo7 = {
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

      useWrapper = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to run oo7-daemon with security wrappers (cap_ipc_lock).";
      };
    };

    # ─── ユーザーごとの設定・s6 サービス ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: {
        options.security.oo7 = {
          enable = mkOption {
            type = types.bool;
            # ★ config.isSessionUser で判定を一元化
            default = cfg.enable && config.isSessionUser;
            description = "ユーザー '${name}' で oo7 キーリングデーモンを起動するかどうか";
          };
        };

        config = mkIf config.security.oo7.enable {
          # ★ 方針Aに従い、s6.services.oo7 に登録
          s6.services.oo7 = {
            type = "longrun";
            dependencies = ["dbus"];
            autoStart = true;
            run = ''
              #!/bin/sh
              exec ${daemonBin}
            '';
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    # 1. パッケージと D-Bus サービスの登録
    environment.systemPackages =
      [
        cfg.serverPackage
        cfg.pamPackage
        pkgs.libsecret
      ]
      ++ optional (pkgs ? oo7-cli) pkgs.oo7-cli;

    services.dbus.packages = [cfg.serverPackage];

    # 2. メモリロック用の security wrapper を登録
    neet.security.wrappers = mkIf cfg.useWrapper {
      oo7-daemon = {
        source = "${cfg.serverPackage}/libexec/oo7-daemon";
        capabilities = ["cap_ipc_lock+ep"];
        owner = "root";
        group = "root";
      };
    };

    # 3. XDG Desktop Portal 連携
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
  };
}
