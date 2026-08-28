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
    # これにより $out/bin/modprobe (busyboxへのリンク) も作成されます
    $out/bin/busybox --install -s $out/bin

    # 3. 重要：既存の modprobe リンクを削除する
    # これをしないと cp が busybox 本体を上書きしようとしてエラーになります
    rm -f $out/bin/modprobe

    # 4. kmod (modprobe) を本物のバイナリで配置
    cp ${pkgs.pkgsStatic.kmod}/bin/kmod $out/bin/modprobe
    chmod 755 $out/bin/modprobe
  '';

  modulesClosure = pkgs.makeModulesClosure {
    # lib.getOutput を使うと、マルチ出力でもシングル出力でも適切にパスを拾える
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
    # Stage 1 の initrd にモジュール群と必要な初期バイナリを配置
    system.build.initrd = pkgs.makeInitrdNG {
      name = "stage1-initrd";
      contents = [
        {
          source = config.system.build.stage1Script;
          target = "/init";
        }
        {
          source = "${initrdEnv}/bin"; # ← bin/ まで含める。suffixは削除。
          target = "/bin";
        }
        {
          source = "${modulesClosure}/lib";
          target = "/lib";
        }
      ];
    };
  };
}
