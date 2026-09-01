{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.mdevd;
  gidOf = name: toString config.neet.gids.${name};
in {
  options.services.mdevd = {
    enable = mkEnableOption "mdevd";
    rules = mkOption {
      type = types.lines;
      default = "";
      description = "mdev.confの内容";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.pkgsStatic.mdevd
      pkgs.pkgsStatic.kmod
      pkgs.pkgsStatic.iproute2
    ];

    environment.etc."mdev.conf".text = cfg.rules;

    system.s6-rc.services = {
      # 1. mdevd デーモン本体
      mdevd = {
        type = "longrun";
        notification-fd = 4;
        run = ''
          #!/bin/execlineb -P
          export PATH /bin:${pkgs.pkgsStatic.mdevd}/bin:${pkgs.pkgsStatic.kmod}/bin
          mdevd -O 4 -f /etc/mdev.conf
        '';
      };

      # 2. coldplug (oneshotとして分離)
      mdevd-coldplug = {
        type = "oneshot";
        dependencies = ["mdevd"];
        up = ''
          #!/bin/execlineb -P
          ${pkgs.pkgsStatic.mdevd}/bin/mdevd-coldplug
        '';
      };
    };

    services.mdevd.rules = lib.mkDefault ''
      -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"

      SUBSYSTEM=net;ACTION=add;.* 0:0 660 @ip link set $INTERFACE up

      null        0:0 666
      zero        0:0 666
      full        0:0 666
      random      0:0 444
      urandom     0:0 444
      tty         0:0 666
      console     0:0 600
      ptmx        0:0 666

      input/.*    0:${gidOf "input"} 660
      dri/.*      0:${gidOf "video"} 660
      video[0-9]+ 0:${gidOf "video"} 660

      tun         0:0 660 =net/
      sd[a-z].*   0:0 660
    '';
  };
}
