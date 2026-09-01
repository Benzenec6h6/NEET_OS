{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  initrdFs = lib.attrValues config.boot.stage1.fileSystems;

  makeMountCmd = fs: let
    opts =
      if fs.options != []
      then "-o ${lib.concatStringsSep "," fs.options}"
      else "";
  in "mkdir -p \"/mnt${fs.mountPoint}\"\nmount -t ${fs.fsType} ${opts} ${fs.device} \"/mnt${fs.mountPoint}\"";

  mountCommands = lib.concatMapStringsSep "\n" makeMountCmd initrdFs;

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
      mountCommands = mountCommands;
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };

  toplevel =
    pkgs.runCommand "neet-os-toplevel" {
      # 依存関係として明示的に認識させる
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
    # 最終的な成果物を system.build に出す（initrd は initrd.nix 内で定義されるため、ここには kernel と stage1Script 等のみ残す）
    system.build.kernel = kernel;
    system.build.stage1Script = stage1Script;
    system.build.stage2Init = stage2Init;
    system.build.toplevel = toplevel;
  };
}
