{
  config,
  pkgs,
  lib,
  ...
}: let
  stage2Init = config.system.build.stage2Init;
  kernelParamsStr = lib.concatStringsSep " " config.boot.kernelParams;

  gfx = config.hardware.graphics.enable or false;
  gfx32 = config.hardware.graphics.enable32Bit or false;
  hasS6 = config.system.build ? s6-rc-db;

  coreJson = pkgs.writeText "neet.json" (builtins.toJSON {
    schema = 1;
    kernelParams = config.boot.kernelParams;
    # 再起動でしか反映できないものだけ。initrd / stage2 / UKI は入れない
    bootFingerprint = lib.concatStringsSep "\n" ([
        "${config.system.build.kernel}"
        "${config.system.modulesTree}"
        "${config.hardware.firmware}"
        kernelParamsStr
      ]
      ++ lib.optional gfx "${config.system.build.graphicsDrivers}");
  });

  # stage2 / initrd / UKI に依存してはいけない(循環するため)
  core = pkgs.runCommand "neet-os-core" {} ''
    mkdir -p $out
    ln -s ${config.system.etc.package} $out/etc
    ln -s ${config.system.path} $out/system-path
    ln -s ${config.system.modulesTree} $out/modules
    ln -s ${config.hardware.firmware} $out/firmware
    ${lib.optionalString hasS6 "ln -s ${config.system.build.s6-rc-db} $out/s6-rc"}
    ${lib.optionalString gfx "ln -s ${config.system.build.graphicsDrivers} $out/graphics-drivers"}
    ${lib.optionalString gfx32 "ln -s ${config.system.build.graphicsDrivers32} $out/graphics-drivers-32bit"}
    cp ${coreJson} $out/neet.json
  '';

  toplevel =
    pkgs.runCommand "neet-os-toplevel" {
      nativeBuildInputs = [pkgs.bash];

      # スクリプトに渡す環境変数
      core = core;
      stage2Init = stage2Init;
      systemPath = config.system.path;
      etc = config.system.etc.package;

      graphicsDrivers = lib.optionalString (config.hardware.graphics.enable or false) config.system.build.graphicsDrivers;
      graphicsDrivers32 = lib.optionalString (config.hardware.graphics.enable32Bit or false) config.system.build.graphicsDrivers32;

      kernel = config.system.build.kernel;
      initrd = config.system.build.initrd;
      kernelParams = kernelParamsStr;

      bootspecWrite = "${config.system.build.bootspecWrite}/bin/bootspec-write";
      hostSystem = pkgs.stdenv.hostPlatform.system;
      kernelVersion = config.boot.kernelPackages.kernel.modDirVersion;

      # UKI が有効ならパスを渡し、無効なら空文字
      uki = lib.optionalString (config.boot.uki.enable or false) "${config.system.build.uki}";

      passthru = {
        inherit stage2Init core;
        systemPath = config.system.path;
        etc = config.system.etc.package;
      };
    } ''
      bash ${./build-toplevel.sh}
    '';
in {
  imports = [
    ./assertions.nix
    ./etc.nix
    ./inieet.nix
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
    system.build.toplevel = config.system.withAssertions toplevel;
    system.build.core = core;
  };
}
