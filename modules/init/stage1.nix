{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  # Stage 2 のための /usr/bin/env（通常の coreutils 固定でOK）
  envBin = "${pkgs.coreutils}/bin/env";

  # Stage 2 のための /bin/sh（sh.nix で指定された通常シェル: 例 dash）
  shBin = "${config.system.path}/bin/sh";

  stage1Script = pkgs.replaceVarsWith {
    src = ./stage1.sh;
    replacements = {
      kernelVersion = "${kernel.modDirVersion}";
      stage2Init = "${config.system.build.stage2Init}";
      kernelModules = lib.concatStringsSep " " config.boot.initrd.availableKernelModules;
      console =
        if config.boot.primaryConsole == "serial"
        then config.boot.serial.device
        else "tty${toString (builtins.head config.boot.vt.consoles)}";
      luksUnlockCommands = config.system.build.luksUnlockCommands or "";

      # Stage 2 側の /mnt/bin/sh, /mnt/usr/bin/env のリンク先
      shBin = shBin;
      envBin = envBin;
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };
in {
  config = {
    system.build.stage1Script = stage1Script;
  };
}
