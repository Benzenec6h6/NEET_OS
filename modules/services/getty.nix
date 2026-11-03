{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.getty;
  dmEnabled = config.services.displayManager.enable or false;
  dmTtyNum = config.services.displayManager.tty;

  # 1. 仮想端末 (VT) 用の agetty サービス生成
  # DMが有効な場合は、そのVT番号 (例: 1) を除外する
  targetVts = lib.optionals config.boot.vt.enable (
    builtins.filter (n: !(dmEnabled && n == dmTtyNum)) config.boot.vt.consoles
  );

  mkVtGettyService = n: let
    tty = "tty${toString n}";
    isAutologin = (cfg.autologinUser != null) && (config.boot.primaryConsole == "vt") && (n == builtins.head config.boot.vt.consoles);
    autologinFlag = lib.optionalString isAutologin "--autologin ${cfg.autologinUser} ";
  in {
    name = "getty-${tty}";
    value = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.util-linux}/bin/agetty ${autologinFlag}--noclear ${tty} linux
      '';
    };
  };

  # 2. シリアル用の agetty サービス生成
  mkSerialGettyService = let
    dev = config.boot.serial.device;
    speed = toString config.boot.serial.speed;
    isAutologin = (cfg.autologinUser != null) && (config.boot.primaryConsole == "serial");
    autologinFlag = lib.optionalString isAutologin "--autologin ${cfg.autologinUser} ";
  in {
    name = "getty-${dev}";
    value = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.util-linux}/bin/agetty ${autologinFlag}--keep-baud ${dev} ${speed} vt220
      '';
    };
  };
in {
  options.services.getty = {
    autologinUser = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "root";
      description = "自動ログインさせるユーザー名（プライマリコンソールにのみ適用）";
    };
  };

  config = {
    system.s6-rc.services = builtins.listToAttrs (
      (map mkVtGettyService targetVts)
      ++ (lib.optional config.boot.serial.enable mkSerialGettyService)
    );
  };
}
