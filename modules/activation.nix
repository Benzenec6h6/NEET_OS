{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    system.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
    };
    system.activationScript = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "システム起動時に実行されるスクリプト";
    };
  };

  config.system.activationScript = pkgs.replaceVarsWith {
    src = ./activate.execline;
    replacements = {
      execline = "${config.environment.execline}";
      systemInitBin = "${config.system.etc.bin}/bin/system-init";
      etcPackage = "${config.system.etc.package}";
      systemPath = "${config.system.path}";
      kernelPath = "${config.boot.kernelPackages.kernel}";
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };
}
