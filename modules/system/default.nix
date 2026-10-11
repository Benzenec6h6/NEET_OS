{
  config,
  pkgs,
  lib,
  ...
}: let
  stage2Init = config.system.build.stage2Init;
  kernelParamsStr = lib.concatStringsSep " " config.boot.kernelParams;

  neetJson = pkgs.writeText "neet.json" (builtins.toJSON {
    schema = 1;
    etc = "${config.system.etc.package}";
    systemPath = "${config.system.path}";
    kernel = "${config.system.build.kernel}";
    modules = "${config.system.modulesTree}";
    firmware = "${config.hardware.firmware}";
    stage2 = "${stage2Init}";
    s6rcCompiled =
      if config.system.build ? s6-rc-db
      then "${config.system.build.s6-rc-db}"
      else null;
    graphicsDrivers =
      if config.hardware.graphics.enable or false
      then "${config.system.build.graphicsDrivers}"
      else null;
    graphicsDrivers32 =
      if config.hardware.graphics.enable32Bit or false
      then "${config.system.build.graphicsDrivers32}"
      else null;
    bootFingerprint = lib.concatStringsSep "\n" ([
        "${config.system.build.kernel}"
        "${config.system.build.initrd}"
        "${config.system.modulesTree}"
        "${config.hardware.firmware}"
        "${stage2Init}"
        kernelParamsStr
      ]
      ++ lib.optional (config.hardware.graphics.enable or false) "${config.system.build.graphicsDrivers}"
      ++ lib.optional (config.boot.uki.enable or false) "${config.system.build.uki}");
  });

  toplevel =
    pkgs.runCommand "neet-os-toplevel" {
      nativeBuildInputs = [pkgs.bash];

      # スクリプトに渡す環境変数
      neetJson = neetJson;
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
        inherit stage2Init;
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
  };
}
