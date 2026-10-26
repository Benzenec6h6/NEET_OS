{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.seatd;
in {
  options.services.seatd = {
    enable = mkEnableOption "seatd daemon";

    group = mkOption {
      type = types.str;
      default = "video";
      description = "Group that owns the seatd socket";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "Enable debug logging for seatd";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.seatd];

    neet.gids.seat = lib.mkDefault 150;

    system.stateDirectories = [
      {
        path = "/run/seatd";
        mode = "0755";
        user = "root";
        group = "seat";
      }
    ];

    system.s6-rc.services.seatd = {
      type = "longrun";
      dependencies = optional config.services.deviceManagerEnable "devd";
      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        ${pkgs.seatd}/bin/seatd -u root -g ${cfg.group} ${optionalString cfg.debug "-l debug"}
      '';
    };
  };
}
