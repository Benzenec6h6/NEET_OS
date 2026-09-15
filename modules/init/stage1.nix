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
      # stage2.nix が定義した成果物を参照
      stage2Init = "${config.system.build.stage2Init}";
      kernelModules = lib.concatStringsSep " " config.boot.initrd.availableKernelModules;
      # boot/default.nix で定義されている boot.consoles を参照
      console = builtins.head config.boot.consoles;
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };
in {
  config = {
    # boot/initrd.nix が拾い上げて /init に配置する
    system.build.stage1Script = stage1Script;
  };
}
