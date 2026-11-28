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
      enable = mkEnableOption "oo7 Secret Service provider (System infrastructure)";

      serverPackage = mkOption {
        type = types.package;
        default = pkgs.oo7-server;
        description = "The package providing oo7-daemon.";
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
          # ★ 自動で気を利かせず、オプトインにする（デフォルト false）
          enable = mkEnableOption "oo7 keyring daemon for user '${name}'";
        };

        config = {
          # ★ 不整合をビルド時に弾く
          assertions = [
            {
              assertion = config.security.oo7.enable -> cfg.enable;
              message = "ユーザー '${name}' で oo7 が有効化されていますが、システム側の 'neet.security.oo7.enable' が無効です。システム側の有効化が必要です。";
            }
          ];

          # s6-rc サービス定義
          s6.services.oo7 = mkIf config.security.oo7.enable {
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
    # クライアント用パッケージ（libsecret 等）を登録
    environment.systemPackages =
      [
        pkgs.libsecret
      ]
      ++ optional (pkgs ? oo7-cli) pkgs.oo7-cli;

    # メモリロック用の security wrapper を登録
    neet.security.wrappers = mkIf cfg.useWrapper {
      oo7-daemon = {
        source = "${cfg.serverPackage}/libexec/oo7-daemon";
        capabilities = ["cap_ipc_lock+ep"];
        owner = "root";
        group = "root";
      };
    };

    # XDG Desktop Portal 連携
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
