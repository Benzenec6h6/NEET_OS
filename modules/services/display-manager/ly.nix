{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;
  lyCfg = config.services.displayManager.ly;

  configFile = pkgs.writeText "ly-config.ini" ''
    tty = ${toString dmCfg.tty}
    session_wrapper = ${dmCfg.sessionWrapper}
    waylandsessions = /run/current-system/sw/share/wayland-sessions
    ${optionalString (dmCfg.defaultSession != "") "default_input = ${dmCfg.defaultSession}"}
    ${optionalString lyCfg.save "save = true"}
    ${optionalString (!lyCfg.save) "save = false"}
  '';
in {
  options.services.displayManager.ly = {
    save = mkOption {
      type = types.bool;
      default = true;
      description = "前回ログインしたユーザーとセッションを記憶するか";
    };
  };

  config = mkIf (dmCfg.enable && dmCfg.provider == "ly") {
    environment.systemPackages = [pkgs.ly];

    system.stateDirectories = [
      {
        path = "/etc/ly";
        mode = "0755";
      }
    ];

    system.s6-rc.services.ly = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.services.seatd.enable "seatd"
        ++ optional config.services.sessiond.enable "sessiond";

      run = ''
        #!/bin/execlineb -P
        fdclose 0
        fdclose 1
        fdclose 2
        redirfd -r 0 /dev/tty${toString dmCfg.tty}
        redirfd -w 1 /dev/tty${toString dmCfg.tty}
        fdmove -c 2 1
        ${pkgs.ly}/bin/ly -c ${configFile}
      '';
    };
  };
}
