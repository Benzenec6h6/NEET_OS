{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.uinput;
  gidOf = name: toString config.neet.gids.${name};
in {
  options.hardware.uinput = {
    enable = lib.mkEnableOption "uinput support";

    group = lib.mkOption {
      type = lib.types.str;
      default = "input";
      description = "Group to own the uinput devices.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = ["uinput"];

    # mdevd.conf にルール追加
    services.mdevd.rules = ''
      -SUBSYSTEM=misc;uinput 0:${gidOf cfg.group} 0660
    '';
  };
}
