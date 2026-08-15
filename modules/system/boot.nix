{
  config,
  pkgs,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;

  # Stage 2 スクリプトの生成
  stage2Init = pkgs.replaceVarsWith {
    src = ./stage2.sh;
    replacements = {
      systemPath = "${config.system.path}";
      s6 = "${pkgs.s6}";
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
