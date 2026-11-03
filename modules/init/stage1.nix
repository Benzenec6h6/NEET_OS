{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  # coreutils のパッケージから env バイナリを確定する
  # （uutils の場合は uu-env になる可能性があるためフォールバックを考慮）
  coreutilsPkg = config.programs.coreutils.package;
  envBin =
    if lib.pathExists "${coreutilsPkg}/bin/env"
    then "${coreutilsPkg}/bin/env"
    else if lib.pathExists "${coreutilsPkg}/bin/uu-env"
    then "${coreutilsPkg}/bin/uu-env"
    else "${pkgs.coreutils}/bin/env";

  # sh バイナリの確定（sh.nix で指定されたパッケージから取得）
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

      # ★ 依存を明示的に注入
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
