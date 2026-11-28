{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.security.gnome-keyring;

  daemonBin =
    if cfg.useWrapper
    then "/run/wrappers/bin/gnome-keyring-daemon"
    else "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon";
in {
  options = {
    neet.security.gnome-keyring = {
      enable = mkEnableOption "GNOME Keyring Secret Service provider";

      useWrapper = mkOption {
        type = types.bool;
        default = true;
        description = "Whether to run gnome-keyring-daemon with security wrappers (cap_ipc_lock).";
      };

      components = mkOption {
        type = types.listOf (types.enum ["secrets" "ssh" "pkcs11"]);
        default = ["secrets"];
        description = "有効にする gnome-keyring コンポーネント。通常は secrets だけで十分です。";
      };
    };

    # ユーザーごとの s6-rc サービス定義
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: {
        options.security.gnome-keyring = {
          enable = mkEnableOption "GNOME Keyring daemon for user '${name}'";
        };

        config = {
          # システム側が無効ならビルド時に弾く
          assertions = [
            {
              assertion = config.security.gnome-keyring.enable -> cfg.enable;
              message = "ユーザー '${name}' で gnome-keyring が有効化されていますが、システム側の 'neet.security.gnome-keyring.enable' が無効です。";
            }
            # 同一ユーザーで oo7 と両方有効になっていないかもチェック
            {
              assertion = !(config.security.gnome-keyring.enable && (config.security.oo7.enable or false));
              message = "ユーザー '${name}' で oo7 と gnome-keyring が同時に有効化されています。";
            }
          ];

          # s6-rc サービス定義
          # gnome-keyring-daemon をフォアグラウンドで立ち上げる
          s6.services.gnome-keyring = mkIf config.security.gnome-keyring.enable {
            type = "longrun";
            dependencies = ["dbus"];
            autoStart = true;

            run = ''
              #!/bin/sh
              exec ${daemonBin} --foreground --components=${concatStringsSep "," cfg.components}
            '';
          };
        };
      }));
    };
  };

  config = mkIf cfg.enable {
    # 基本ライブラリ
    environment.systemPackages = [
      pkgs.gnome-keyring
      pkgs.libsecret
    ];

    # メモリロック用 wrapper (スワップへの秘密鍵漏洩防止)
    neet.security.wrappers = mkIf cfg.useWrapper {
      gnome-keyring-daemon = {
        source = "${pkgs.gnome-keyring}/bin/gnome-keyring-daemon";
        capabilities = ["cap_ipc_lock+ep"];
        owner = "root";
        group = "root";
      };
    };
  };
}
