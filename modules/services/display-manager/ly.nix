{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;
  lyCfg = config.services.displayManager.ly;

  # ly の設定ファイル (config.ini)
  configFile = pkgs.writeText "ly-config.ini" ''
    tty = ${toString dmCfg.tty}

    # 人間ユーザーのみ表示 (nixbld や root を除外)
    min_uid = 1000
    max_uid = 60000

    # X11 サポートを完全無効化 (xinitrc や x11 セッションを出さない)
    load = false

    # Wayland セッションの探索パス
    waylandsessions = /etc/wayland-sessions

    # セッション起動ラッパー
    session_wrapper = ${dmCfg.sessionWrapper}

    ${optionalString (dmCfg.defaultSession != "") "default_input = ${dmCfg.defaultSession}"}
    ${optionalString lyCfg.save "save = true"}
    ${optionalString (!lyCfg.save) "save = false"}
  '';
in {
  options.services.displayManager.ly = {
    save = mkOption {
      type = types.bool;
      default = true;
      description = "前回ログインしたユーザーとセッションを記憶するか";
    };
  };

  config = mkIf (dmCfg.enable && dmCfg.provider == "ly") {
    environment.systemPackages = [pkgs.ly];

    # ly は /etc/ly/config.ini を見に行く場合があるため念のため配置
    environment.etc."ly/config.ini".source = configFile;

    system.stateDirectories = [
      {
        path = "/etc/ly";
        mode = "0755";
      }
    ];

    system.s6-rc.services.ly = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.services.seatd.enable "seatd"
        ++ optional config.services.sessiond.enable "sessiond";

      run = ''
        #!/bin/execlineb -P
        fdclose 0
        fdclose 1
        fdclose 2
        redirfd -r 0 /dev/tty${toString dmCfg.tty}
        redirfd -w 1 /dev/tty${toString dmCfg.tty}
        fdmove -c 2 1
        ${pkgs.ly}/bin/ly -c ${configFile}
      '';
    };
  };
}
