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
      default = "seat";
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

    system.s6-rc.services.seatd = {
      type = "longrun";
      notification-fd = 3;
      dependencies = optional config.services.deviceManagerEnable "device-manager";
      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        # ★ -s を削除し、-n 3 で s6-rc に準備完了を通知
        ${pkgs.seatd}/bin/seatd -n 3 -u root -g ${cfg.group} ${optionalString cfg.debug "-l debug"}
      '';
    };
  };
}
