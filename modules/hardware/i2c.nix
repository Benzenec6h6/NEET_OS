{
  config,
  lib,
  ...
}: let
  cfg = config.hardware.i2c;
  gidOf = name: toString config.neet.gids.${name};
in {
  options.hardware.i2c = {
    enable = lib.mkEnableOption "support for i2c devices";

    group = lib.mkOption {
      type = lib.types.str;
      default = "i2c";
      description = "Group to own the /dev/i2c-* devices.";
    };
  };

  config = lib.mkIf cfg.enable {
    boot.kernelModules = ["i2c-dev"];

    # i2c グループの GID を確保
    neet.gids = lib.optionalAttrs (cfg.group == "i2c") {
      i2c = lib.mkDefault 302;
    };

    # mdevd.conf にルール追加
    services.mdevd.rules = ''
      i2c-[0-9]*  0:${gidOf cfg.group} 660
    '';
  };
}
