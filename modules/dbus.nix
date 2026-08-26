{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.dbus;

  homeDir = "/run/dbus";

  # Nixのヘルパーを使ってXML設定ディレクトリを自動生成
  configDir = pkgs.makeDBusConf.override {
    serviceDirectories = cfg.packages;
  };

  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.services.dbus = {
    enable = mkEnableOption "D-Bus system message bus daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.dbus;
      defaultText = lib.literalExpression "pkgs.dbus";
      description = "使用する D-Bus パッケージ";
    };

    packages = mkOption {
      type = types.listOf types.path;
      default = [];
      description = ''
        D-Bus設定ファイルを取り込むパッケージのリスト。
      '';
    };
  };

  config = mkIf cfg.enable {
    # 1. 生成された完全な /etc/dbus-1 を配置
    environment.etc."dbus-1".source = configDir;

    # 2. NEET-OS 独自のユーザー・グループ定義に messagebus を注入
    neet.users.messagebus = {
      uid = 81;
      gid = 81;
      shell = "/bin/false";
      home = homeDir;
      description = "D-Bus system message bus daemon user";
    };

    # 3. システムパッケージ & パス設定
    environment.systemPackages = [cfg.package];

    services.dbus.packages =
      [
        cfg.package
      ]
      ++ config.environment.systemPackages;

    # 4. s6-scan 経由での D-Bus システムデーモン起動定義
    environment.etc = {
      "s6-scan/dbus/run" = {
        text = ''
          #!/bin/execlineb -P
          foreground { mkdir -p /run/dbus /var/lib/dbus /run/lock/subsys }
          foreground { chown messagebus:messagebus /run/dbus /var/lib/dbus }
          foreground { ${cfg.package}/bin/dbus-uuidgen --ensure }

          ${cfg.package}/bin/dbus-daemon --nofork --system --syslog-only
        '';
        mode = "0555";
      };
    };
  };
}
