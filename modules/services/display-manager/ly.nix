{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;
  lyCfg = config.services.displayManager.ly;

  # デフォルトで選択させたい最初の一般ユーザー名
  firstUser = head (attrNames config.neet.sessionUsers);

  # ly の設定ファイル (config.ini)
  configFile = pkgs.writeText "ly-config.ini" ''
    tty = ${toString dmCfg.tty}

    # ★ X11 および xinitrc を完全に無効化 (null に指定)
    xinitrc = null
    xsessions = null

    # ★ Wayland セッションの探索パス
    waylandsessions = /etc/wayland-sessions

    # セッション起動ラッパー
    session_wrapper = ${dmCfg.sessionWrapper}

    # 前回ログインの記憶設定
    save = ${boolToString lyCfg.save}
    load = ${boolToString lyCfg.save}

    # ★ 初期フォーカス（nixbld ではなく宣言されたユーザーを初期選択させる）
    default_input = ${firstUser}
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

    # ly は自動的に /etc/ly/config.ini を読み込む
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
        # ★ 引数なし (または -c <TTY番号>) で呼ぶ。設定ファイルパスを渡してはならない
        ${pkgs.ly}/bin/ly -c ${toString dmCfg.tty}
      '';
    };
  };
}
