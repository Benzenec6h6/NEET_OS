{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.sessiond-uaccess;

  configFile = pkgs.writeTextDir "00-neet.lua" cfg.extraConfig;

  # deviceManager の選択に応じて libudev バックエンドを自動切り替え
  udevApi =
    if config.services.deviceManager == "gardendevd"
    then pkgs.libudev-garden
    else if config.services.deviceManager == "mdevd"
    then pkgs.libudev-zero
    else null;
in {
  options.services.sessiond-uaccess = {
    enable = lib.mkEnableOption "sessiond-uaccess daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sessiond-uaccess.override (
        lib.optionalAttrs (udevApi != null) {
          udev = udevApi;
        }
      );
      defaultText = lib.literalExpression "pkgs.sessiond-uaccess";
      description = "The package to use for sessiond-uaccess.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable debug logging.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Additional lua rules for sessiond-uaccess.";
    };
  };

  config = lib.mkIf cfg.enable {
    # sessiond 自体が有効化されている必要がある
    services.sessiond.enable = true;

    # s6-rc サービス定義
    system.s6-rc.services.sessiond-uaccess = {
      type = "longrun";
      dependencies = ["sessiond"];
      run = ''
        #!/bin/sh
        export LOG_LEVEL="${
          if cfg.debug
          then "debug"
          else "info"
        }"
        exec ${lib.getExe cfg.package} \
          --log-target stderr \
          --rules-dirs ${cfg.package}/share/sessiond-uaccess/rules \
          ${lib.optionalString (cfg.extraConfig != "") "--rules-dirs ${configFile}"}
      '';
    };
  };
}
