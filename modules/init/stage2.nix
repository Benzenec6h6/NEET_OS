{
  config,
  pkgs,
  lib,
  ...
}: let
  stage2Init = pkgs.replaceVarsWith {
    src = ./stage2.execline;
    replacements = {
      execline = "${config.environment.execline}";
      systemPath = "${config.system.path}";
      systemInitBin = "${config.system.etc.bin}/bin/system-init";
      etcPackage = "${config.system.etc.package}";
      kernelPath = "${config.system.modulesTree}";
      firmwarePackage = "${config.hardware.firmware}";
    };
    isExecutable = true;
  };
in {
  config = {
    # system/default.nix と stage1.nix の両方から参照される
    system.build.stage2Init = stage2Init;
  };
}
