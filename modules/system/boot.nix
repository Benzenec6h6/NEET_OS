{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  # Stage 2 スクリプトの生成
  stage2Init = pkgs.replaceVarsWith {
    src = ./stage2.execline;
    replacements = {
      execline = "${config.environment.execline}";
      systemPath = "${config.system.path}";
      activationScript = "${config.system.activationScript}";
    };
    isExecutable = true;
  };

  # Stage 1 スクリプトの生成
  stage1Script = pkgs.replaceVarsWith {
    src = ./stage1.sh;
    replacements = {
      kernelVersion = "${kernel.modDirVersion}";
      systemPath = "${config.system.path}";
      stage2Init = "${stage2Init}";
      kernelModules = lib.concatStringsSep " " config.boot.initrd.availableKernelModules;
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };

  toplevel =
    pkgs.runCommand "neet-os-toplevel" {
      passthru = {
        inherit stage2Init;
        systemPath = config.system.path;
        etc = config.system.etc.package;
      };
    } ''
      mkdir -p $out
      ln -s ${stage2Init} $out/init
      ln -s ${config.system.path} $out/system-path
      ln -s ${config.system.etc.package} $out/etc
    '';
in {
  imports = [
    ../boot/kernel.nix
    ../boot/initrd.nix
  ];

  options = {
    system.build = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = {};
      description = "ビルド成果物（カーネル、initrdなど）を格納する属性セット";
    };
  };

  config = {
    system.build.kernel = kernel;
    system.build.stage1Script = stage1Script;
    system.build.stage2Init = stage2Init;
    system.build.toplevel = toplevel;
  };
}
