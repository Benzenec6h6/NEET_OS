{
  pkgs,
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.neet.security.polkit;
in {
  imports = [
    ./hyprpolkitagent.nix
    ./cmd-polkit.nix
  ];

  options.neet.security.polkit = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable Polkit daemon.";
    };

    agent = mkOption {
      type = types.nullOr (types.enum ["hyprpolkitagent" "cmd-polkit"]);
      default = "hyprpolkitagent";
      description = "使用するグラフィカル Polkit 認証エージェント (null の場合はなし)";
    };
  };

  config = mkIf cfg.enable {
    services.dbus.packages = [pkgs.polkit.out];
    environment.systemPackages = [pkgs.polkit];

    neet.gids.polkituser = mkDefault 999;
    neet.users.polkituser = {
      uid = mkDefault 999;
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
        ++ optional config.services.syslog.enable "syslog";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
      '';
    };
  };
}
