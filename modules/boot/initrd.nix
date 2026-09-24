{
  config,
  pkgs,
  lib,
  ...
}: let
  # ビルド用スクリプトの生成（変数の注入）
  buildInitrdEnvScript = pkgs.replaceVarsWith {
    src = ./build-initrd.sh;
    replacements = {
      busybox = "${pkgs.pkgsStatic.busybox}";
      kmod = "${pkgs.pkgsStatic.kmod}";
      utilLinux = "${pkgs.pkgsStatic.util-linux}";
      mdevd = "${pkgs.pkgsStatic.mdevd}";
      earlyInit = "${config.system.build.earlyInit}";
      mdevdDiskScript = "${config.system.build.mdevdDisk}/bin/mdevd-disk.sh";
    };
    isExecutable = true;
  };

  # スクリプトを実行して initrdEnv を生成
  initrdEnv = pkgs.runCommand "initrd-env" {} ''
    export out=$out
    ${buildInitrdEnvScript}
  '';

  modulesClosure = pkgs.makeModulesClosure {
    kernel = lib.getOutput "modules" config.boot.kernelPackages.kernel;
    rootModules = lib.unique config.boot.initrd.availableKernelModules;
    firmware = pkgs.linux-firmware;
    allowMissing = true;
  };
in {
  options.boot.initrd = {
    availableKernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Stage 1 で利用可能にするモジュール";
    };
    prepend = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "initrd の先頭に連結する非圧縮 cpio イメージのリスト（マイクロコード等）";
    };
  };
  config = {
    system.build.debugModulesClosure = modulesClosure;
    system.build.initrd = pkgs.makeInitrdNG {
      name = "stage1-initrd";
      prepend = config.boot.initrd.prepend;
      contents = [
        {
          source = config.system.build.stage1Script;
          target = "/init";
        }
        {
          source = "${initrdEnv}/bin";
          target = "/bin";
        }
        {
          source = "${modulesClosure}/lib";
          target = "/lib";
        }
        {
          source = pkgs.writeText "mdev.conf" config.services.mdevd.rules;
          target = "/etc/mdev.conf";
        }
        {
          source = config.system.build.stage1MountPlan;
          target = "/mount-plan.json";
        }
      ];
    };
  };
}
