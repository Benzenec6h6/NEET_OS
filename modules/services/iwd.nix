{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.iwd;
  format = pkgs.formats.ini {};
in {
  options.services.iwd = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "iwd (Wireless Daemon) をシステムサービスとして有効化するかどうか";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.iwd;
      defaultText = literalExpression "pkgs.iwd";
      description = "使用する iwd パッケージ";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "デバッグログを有効化するかどうか";
    };

    settings = mkOption {
      type = format.type;
      default = {};
      description = "iwd の設定 (詳細は iwd.config(5) を参照)";
    };
  };

  config = mkIf cfg.enable {
    services.iwd.settings = {
      General = {
        # iwd 内蔵の DHCP クライアントを有効化
        EnableNetworkConfiguration = mkDefault true;
      };

      Network = {
        # resolvconf が有効なら openresolv と自動連携させる
        NameResolvingService =
          if config.programs.resolvconf.enable
          then "resolvconf"
          else "none";
      };
    };

    # iwctl コマンド等を一般環境で利用可能にする
    environment.systemPackages = [cfg.package];

    # /etc/iwd/main.conf の生成
    environment.etc."iwd/main.conf".source = format.generate "main.conf" cfg.settings;

    # D-Bus のポリシーファイルを配置
    services.dbus.packages = [cfg.package];

    # s6-rc: longrun サービス定義
    system.s6-rc.services.iwd = {
      type = "longrun";
      dependencies =
        optional config.services.dbus.enable "dbus"
        ++ optional config.services.mdevd.enable "mdevd-coldplug"
        ++ optional (config.system.s6-rc.services ? sysctl) "sysctl"
        ++ optional (config.system.s6-rc.services ? resolvconf) "resolvconf";

      run = ''
        #!/bin/sh
        # 1. 接続プロファイル用ディレクトリの作成 (パーミッション 0700 が必須)
        mkdir -p /var/lib/iwd
        chmod 0700 /var/lib/iwd

        # 2. resolvconf を iwd が呼び出せるように PATH を通す
        export PATH="${makeBinPath (optional config.programs.resolvconf.enable config.programs.resolvconf.package)}:$PATH"

        # 3. iwd をフォアグラウンドで起動 (iwd はデフォルトでフォアグラウンド実行)
        exec ${cfg.package}/libexec/iwd${optionalString cfg.debug " -d"}
      '';
    };
  };
}
