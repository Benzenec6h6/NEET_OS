{
  config,
  pkgs,
  lib,
  ...
}: let
  stage2Init = config.system.build.stage2Init;
  kernelParamsStr = lib.concatStringsSep " " config.boot.kernelParams;

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

       # === グラフィックスドライバ (rebuild.sh での比較用) ===
      ${lib.optionalString (config.hardware.graphics.enable or false) ''
        ln -s ${config.system.build.graphicsDrivers} $out/graphics-drivers
        ${lib.optionalString (config.hardware.graphics.enable32Bit or false) ''
          ln -s ${config.system.build.graphicsDrivers32} $out/graphics-drivers-32bit
        ''}
      ''}

      # === ブート用 ===
      # カーネル
      if [ -f "${config.system.build.kernel}/bzImage" ]; then
        ln -s ${config.system.build.kernel}/bzImage $out/kernel
      else
        ln -s ${config.system.build.kernel} $out/kernel
      fi

      # initrd: ディレクトリ内の実ファイル (initrd) を指すように変更
      if [ -f "${config.system.build.initrd}/initrd" ]; then
        ln -s ${config.system.build.initrd}/initrd $out/initrd
      else
        ln -s ${config.system.build.initrd} $out/initrd
      fi

      # カーネルパラメータ
      echo "${kernelParamsStr}" > $out/kernel-params
    '';
in {
  imports = [
    ./etc
    ./users.nix
    ./environment.nix
    ./shells.nix
  ];

  options = {
    system.build = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = {};
      description = "システム全体のビルド成果物を格納する属性セット";
    };
  };

  config = {
    system.build.toplevel = toplevel;
  };
}
