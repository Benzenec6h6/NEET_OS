{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.getty;
  primaryConsole = builtins.head config.boot.consoles;

  # DMが有効な場合はそのTTY（例: "tty1"）を取得してagettyの対象から外す
  dmTty =
    if (config.services.displayManager.enable or false)
    then "tty${toString config.services.displayManager.tty}"
    else null;

  activeConsoles = builtins.filter (tty: tty != dmTty) config.boot.consoles;

  mkGettyCmd = tty: let
    isSerial = lib.hasPrefix "ttyS" tty || lib.hasPrefix "ttyUSB" tty;
    isAutologin = (cfg.autologinUser != null) && (tty == primaryConsole);

    flags =
      lib.optional isAutologin "--autologin ${cfg.autologinUser}"
      ++ (
        if isSerial
        then ["--keep-baud"]
        else ["--noclear"]
      );

    args =
      [tty]
      ++ (
        if isSerial
        then [
          (toString config.boot.serialSpeed)
          "vt220"
        ]
        else ["linux"]
      );
  in "${pkgs.util-linux}/bin/agetty ${lib.concatStringsSep " " (flags ++ args)}";

  mkGettyService = tty: {
    name = "getty-${tty}";
    value = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        ${mkGettyCmd tty}
      '';
    };
  };
in {
  options.services.getty = {
    autologinUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "root";
      description = "自動ログインさせるユーザー名（プライマリコンソールのみに適用）";
    };
  };

  config = {
    system.s6-rc.services = builtins.listToAttrs (map mkGettyService activeConsoles);
  };
}
