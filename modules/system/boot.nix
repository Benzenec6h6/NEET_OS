{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  initrdFs = lib.filter (fs: fs.neededForBoot) (lib.attrValues config.fileSystems);

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
      # environment.nix で定義した system.path を参照
      systemPath = "${config.system.path}";

      # environment.nix で定義した execline パッケージを参照
      execline = "${config.environment.execline}";

      # pkgsStatic.s6 (ここは直接 pkgs から取っても、オプション化してもOK)
      s6 = "${pkgs.pkgsStatic.s6}";

      # activation.nix / etc/default.nix で定義されているはずのオプション
      systemInit = "${config.system.etc.bin}";
      etcPackage = "${config.system.etc.package}";
      kernelPath = "${config.boot.kernelPackages.kernel.modules}";
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
  };
}
