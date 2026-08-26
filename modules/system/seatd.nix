{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.seatd;
in {
  options.services.seatd = {
    enable = lib.mkEnableOption "seatd daemon";

    group = lib.mkOption {
      type = lib.types.str;
      default = "video";
      description = "Group that owns the seatd socket";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Enable debug logging for seatd";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [pkgs.pkgsStatic.seatd];

    environment.etc = {
      "s6-scan/seatd/run" = {
        text = ''
          #!/bin/execlineb -P
          fdmove -c 2 1
          ${pkgs.pkgsStatic.seatd}/bin/seatd -u root -g ${cfg.group} ${lib.optionalString cfg.debug "-l debug"}
        '';
        mode = "0555";
      };

      "s6-scan/seatd/log/run" = {
        text = ''
          #!/bin/execlineb -P
          foreground { mkdir -p /var/log/seatd }
          s6-log n3 s1000000 /var/log/seatd
        '';
        mode = "0555";
      };
    };
  };
}
