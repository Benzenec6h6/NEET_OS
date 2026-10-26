{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.neet.security.polkit;
in {
  options.neet.security.polkit = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable Polkit daemon.";
    };
  };

  # ★ 自身の cfg.enable を見るように変更
  config = lib.mkIf cfg.enable {
    services.dbus.packages = [pkgs.polkit.out];
    environment.systemPackages = [pkgs.polkit];

    # 先ほど整理したユーザー・グループ・ディレクトリ等
    neet.gids.polkituser = lib.mkDefault 999;
    neet.users.polkituser = {
      uid = lib.mkDefault 999;
      gid = config.neet.gids.polkituser;
      description = "Polkit daemon user";
      shell = "/bin/sh";
      home = "/var/empty";
      createHome = false;
      createRuntimeDir = false;
    };

    system.stateDirectories = [
      {
        path = "/var/lib/polkit-1";
        mode = "0700";
        user = "polkituser";
        group = "polkituser";
      }
    ];

    environment.etc."polkit-1/rules.d/50-default.rules".text = ''
      polkit.addAdminRule(function(action, subject) {
          return ["unix-group:wheel"];
      });
    '';

    system.s6-rc.services.polkitd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ lib.optional config.services.syslog.enable "syslog";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
      '';
    };
  };
}
