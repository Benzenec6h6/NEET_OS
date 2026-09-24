{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.hardware.graphics;

  driversEnv = pkgs.buildEnv {
    name = "graphics-drivers";
    paths = [cfg.package] ++ cfg.extraPackages;
  };

  driversEnv32 = pkgs.buildEnv {
    name = "graphics-drivers-32bit";
    paths = [cfg.package32] ++ cfg.extraPackages32;
  };
in {
  options.hardware.graphics = {
    enable = lib.mkEnableOption "hardware accelerated graphics drivers";

    enable32Bit = lib.mkOption {
      description = "On 64-bit systems, whether to also install 32-bit drivers.";
      type = lib.types.bool;
      default = false;
    };

    package = lib.mkOption {
      description = "The package that provides the default driver set.";
      type = lib.types.package;
      internal = true;
    };

    package32 = lib.mkOption {
      description = "The package that provides the 32-bit driver set.";
      type = lib.types.package;
      internal = true;
    };

    extraPackages = lib.mkOption {
      description = "Additional packages to add to the driver lookup path.";
      type = lib.types.listOf lib.types.package;
      default = [];
    };

    extraPackages32 = lib.mkOption {
      description = "Additional packages for 32-bit driver lookup path.";
      type = lib.types.listOf lib.types.package;
      default = [];
    };
  };

  config = lib.mkIf cfg.enable {
    hardware.graphics.package = lib.mkDefault pkgs.mesa;
    hardware.graphics.package32 = lib.mkDefault pkgs.pkgsi686Linux.mesa;

    # ビルド成果物をエクスポート
    system.build.graphicsDrivers = driversEnv;
    system.build.graphicsDrivers32 = driversEnv32;
  };
}
