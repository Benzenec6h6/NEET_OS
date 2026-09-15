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
    environment.systemPackages = [pkgs.pkgsStatic.seatd];

    system.s6-rc.services.seatd = {
      type = "longrun";
      dependencies = optional config.services.mdevd.enable "mdevd";
      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        ${pkgs.pkgsStatic.seatd}/bin/seatd -u root -g ${cfg.group} ${optionalString cfg.debug "-l debug"}
      '';
    };
  };
}
