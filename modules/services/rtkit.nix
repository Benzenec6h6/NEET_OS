{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.rtkit;
  inherit (lib) mkOption mkEnableOption mkIf types;
in {
  options.services.rtkit = {
    enable = mkEnableOption "RealtimeKit scheduling policy service";

    package = mkOption {
      type = types.package;
      default = pkgs.rtkit;
      description = "The package to use for rtkit.";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable debug logging.";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # 1. D-Bus への登録 (rtkit は D-Bus 経由で呼び出される)
    services.dbus.enable = true;
    services.dbus.packages = [cfg.package];

    # 2. NEET_OS ユーザー・グループ定義
    neet.gids.rtkit = lib.mkDefault 172;

    neet.users.rtkit = {
      uid = 172;
      gid = config.neet.gids.rtkit;
      shell = "/bin/false";
      home = "/proc";
      createHome = false;
      createRuntimeDir = false;
      description = "RealtimeKit daemon user";
    };

    # 3. s6-rc サービス定義 (dbus と polkitd に依存)
    system.s6-rc.services.rtkit-daemon = {
      type = "longrun";
      dependencies = ["dbus" "polkitd"];
      run = ''
        #!/bin/execlineb -P
        ${cfg.package}/libexec/rtkit-daemon${lib.optionalString cfg.debug " --debug"}
      '';
    };

    # 4. Polkit ルール (wheel グループやオーディオユーザーが realtime 要求できるようにする)
    environment.etc."polkit-1/rules.d/50-rtkit.rules".text = ''
      polkit.addRule(function(action, subject) {
        if (action.id == "org.freedesktop.RealtimeKit1.acquire-high-priority" ||
            action.id == "org.freedesktop.RealtimeKit1.acquire-real-time") {
          return polkit.Result.YES;
        }
        return polkit.Result.NOT_HANDLED;
      });
    '';
  };
}
