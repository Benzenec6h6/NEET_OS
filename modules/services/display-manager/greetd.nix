{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;

  # tuigreet に /etc/wayland-sessions を読ませる
  greetdConfig = pkgs.writeText "greetd.toml" ''
    [terminal]
    vt = ${toString dmCfg.tty}

    [default_session]
    command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --sessions /etc/wayland-sessions ${optionalString (dmCfg.defaultSession != "") "--cmd ${dmCfg.defaultSession}"}"
    user = "greeter"
  '';
in {
  config = mkIf (dmCfg.enable && dmCfg.provider == "greetd") {
    environment.systemPackages = [
      pkgs.greetd.greetd
      pkgs.greetd.tuigreet
    ];

    neet.users.greeter = {
      uid = mkDefault 970;
      gid = mkDefault 970;
      description = "greetd greeter user";
      home = "/var/lib/greetd";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = true;
      createRuntimeDir = true;
    };

    system.stateDirectories = [
      {
        path = "/var/lib/greetd";
        mode = "0750";
        user = "greeter";
        group = "greeter";
      }
    ];

    system.s6-rc.services.greetd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.services.seatd.enable "seatd"
        ++ optional config.services.sessiond.enable "sessiond";

      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        ${pkgs.greetd.greetd}/bin/greetd --config ${greetdConfig}
      '';
    };
  };
}
