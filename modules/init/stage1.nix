{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  stage1Script = pkgs.replaceVarsWith {
    src = ./stage1.sh;
    replacements = {
      kernelVersion = "${kernel.modDirVersion}";
      systemPath = "${config.system.path}";
      stage2Init = "${config.system.build.stage2Init}";
      kernelModules = lib.concatStringsSep " " config.boot.initrd.availableKernelModules;
      console = builtins.head config.boot.consoles;
      luksUnlockCommands = config.system.build.luksUnlockCommands or "";
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };
in {
  config = {
    system.build.stage1Script = stage1Script;
  };
}
