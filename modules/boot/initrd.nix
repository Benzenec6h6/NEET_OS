{
  config,
  pkgs,
  lib,
  ...
}: let
  initrdEnv = pkgs.runCommand "initrd-env" {} ''
    mkdir -p $out/bin
    # 1. BusyBox 本体の配置（書き込み権限を付与）
    cp ${pkgs.pkgsStatic.busybox}/bin/busybox $out/bin/busybox
    chmod 755 $out/bin/busybox
    # 2. BusyBox の全リンク（sh, mount, mkdir等）を作成
    $out/bin/busybox --install -s $out/bin
    # 3. 既存の modprobe リンクを削除
    rm -f $out/bin/modprobe
    # 4. kmod (modprobe) を本物のバイナリで配置
    cp ${pkgs.pkgsStatic.kmod}/bin/kmod $out/bin/modprobe
    chmod 755 $out/bin/modprobe
    # 5. early-init を配置（busyboxと対称的に実体コピー）
    cp ${config.system.build.earlyInit}/bin/early-init $out/bin/early-init
    chmod 755 $out/bin/early-init
  '';
  modulesClosure = pkgs.makeModulesClosure {
    kernel = lib.getOutput "modules" config.boot.kernelPackages.kernel;
    rootModules = lib.unique config.boot.initrd.availableKernelModules;
    firmware = pkgs.linux-firmware;
    allowMissing = true;
  };
in {
  options.boot.initrd.availableKernelModules = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [];
    description = "Stage 1 で利用可能にするモジュール";
  };
  config = {
    system.build.debugModulesClosure = modulesClosure;
    system.build.initrd = pkgs.makeInitrdNG {
      name = "stage1-initrd";
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
          source = config.system.build.stage1MountPlan;
          target = "/mount-plan.json";
        }
      ];
    };
  };
}
