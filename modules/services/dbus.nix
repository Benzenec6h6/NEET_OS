{
  config,
  pkgs,
  lib,
  ...
}: let
  runtimeUsers =
    lib.filterAttrs (
      _name: u:
        u.createRuntimeDir
        && u.uid >= 1000
    )
    config.neet.users;

  userBusServices =
    lib.mapAttrs' (
      name: u: let
        uidStr = toString u.uid;
        runtimeDir = "/run/user/${uidStr}";
        busAddress = "unix:path=${runtimeDir}/bus";
      in
        lib.nameValuePair "dbus-user-${name}" {
          type = "longrun";
          dependencies = ["dbus"];
          notification-fd = 3;
          # ディレクトリ作成は Rust に任せ、s6 は環境変数設定と権限降格だけを行う
          run = ''
            #!/bin/execlineb -P
            export XDG_RUNTIME_DIR ${runtimeDir}
            export DBUS_SESSION_BUS_ADDRESS ${busAddress}
            exec ${pkgs.s6}/bin/s6-notify-fd-from-socket -3 3 \
            ${pkgs.s6}/bin/s6-setuidgid ${name} \
            ${cfg.package}/bin/dbus-daemon --session --address="${busAddress}" --nofork --nopidfile --syslog-only
          '';
        }
    )
    runtimeUsers;

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

    userBus.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "createRuntimeDir が有効なユーザー向けの D-Bus User Bus を自動起動するか";
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
      [cfg.package]
      ++ config.environment.systemPackages;

    # 4. s6-scan 経由での D-Bus システムデーモン起動定義
    system.s6-rc.services =
      {
        dbus = {
          type = "longrun";
          notification-fd = 3;
          run = ''
            #!/bin/sh
            mkdir -p /run/dbus /var/lib/dbus /run/lock/subsys
            chown messagebus:messagebus /run/dbus /var/lib/dbus
            ${cfg.package}/bin/dbus-uuidgen --ensure

            # ★ sd_notify を s6 の fd 3 に変換して通知
            exec ${pkgs.s6}/bin/s6-notify-fd-from-socket -3 3 \
              ${cfg.package}/bin/dbus-daemon --nofork --system --syslog-only
          '';
        };
      }
      // lib.optionalAttrs cfg.userBus.enable userBusServices;
  };
}
