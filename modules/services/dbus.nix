{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.dbus;
  homeDir = "/run/dbus";

  configDir = pkgs.makeDBusConf.override {
    serviceDirectories = cfg.packages;
  };
in {
  options.services.dbus = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "D-Bus system message bus daemon";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.dbus;
      description = "使用する D-Bus パッケージ";
    };

    packages = mkOption {
      type = types.listOf types.path;
      default = [];
      description = "D-Bus設定ファイルを取り込むパッケージのリスト。";
    };
  };

  config = mkIf cfg.enable {
    environment.etc."dbus-1".source = configDir;

    neet.users.messagebus = {
      uid = 81;
      gid = 81;
      shell = "/bin/false";
      home = homeDir;
      description = "D-Bus system message bus daemon user";
    };

    environment.systemPackages = [cfg.package];

    services.dbus.packages =
      [cfg.package]
      ++ config.environment.systemPackages;

    system.stateDirectories = [
      {
        path = "/run/dbus";
        mode = "0755";
        user = "messagebus";
        group = "messagebus";
      }
      {
        path = "/var/lib/dbus";
        mode = "0755";
        user = "root";
        group = "root";
      }
      {
        path = "/run/lock/subsys";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # システム s6-rc: システムバスのみ
    system.s6-rc.services.dbus = {
      type = "longrun";
      notification-fd = 3;
      dependencies = optional config.services.syslog.enable "syslog";
      log.enable = true;
      run = ''
        #!/bin/execlineb -P
        foreground { ${cfg.package}/bin/dbus-uuidgen --ensure }
        ${cfg.package}/bin/dbus-daemon --nofork --system --syslog-only --print-pid=3
      '';
    };

    # ★ ユーザー s6-rc: 各ユーザーのツリーに純粋な "dbus" として自動登録！
    system.s6-rc.users =
      mapAttrs (name: u: {
        services.dbus = {
          type = "longrun";
          notification-fd = 3;
          run = ''
            #!/bin/sh
            exec ${cfg.package}/bin/dbus-daemon --session --address="unix:path=$XDG_RUNTIME_DIR/bus" --nofork --nopidfile --print-pid=3
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
