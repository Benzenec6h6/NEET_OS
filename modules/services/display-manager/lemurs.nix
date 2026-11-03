{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;
  lemursCfg = config.services.displayManager.lemurs;

  format = pkgs.formats.toml {};

  # デフォルト設定
  defaultSettings = {
    tty = dmCfg.tty;
    pam_service = "lemurs";

    # ログイン後の初期PATH（neet-activate のラッパーやシステムパス）
    initial_path = "/run/wrappers/bin:/etc/profiles/per-user/$USER/bin:/run/current-system/sw/bin";

    # 既存の /etc/wayland-sessions (*.desktop) を検索させる
    wayland = {
      wayland_sessions_path = "/etc/wayland-sessions";
    };

    # もしLemurs上から直接セッションラッパーを叩くシェルスクリプト形式にしたい場合のディレクトリ
    # （空のディレクトリを作っておけば問題ありません）
    wayland_environments_path = "/etc/lemurs/wayland";
    wms_environments_path = "/etc/lemurs/wms";

    # 電源操作キー (不要なら外しても動作します)
    power_controls = {
      base_entries = [
        {
          hint = "Shutdown";
          hint_color = "dark gray";
          hint_modifiers = "";
          key = "F1";
          # NEET_OS のシャットダウンコマンドに合わせて変更してください
          cmd = "/run/wrappers/bin/shutdown || /run/current-system/sw/bin/poweroff";
        }
        {
          hint = "Reboot";
          hint_color = "dark gray";
          hint_modifiers = "";
          key = "F2";
          cmd = "/run/wrappers/bin/reboot || /run/current-system/sw/bin/reboot";
        }
      ];
    };
  };

  lemursSettings = recursiveUpdate defaultSettings lemursCfg.settings;
  configFile = format.generate "lemurs-config.toml" lemursSettings;

  # lemursのセッション選択から hyprland や sway が選ばれた時に、
  # 引数つきで userSessionRunner を呼ぶようにするセッションスクリプト（フォールバック用）
  sessionLauncher = pkgs.writeShellScript "lemurs-session-launcher" ''
    exec ${dmCfg.sessionWrapper} "$1"
  '';
in {
  options.services.displayManager.lemurs = {
    settings = mkOption {
      type = format.type;
      default = {};
      description = "Lemurs の config.toml にマージする追加設定";
    };
  };

  config = mkIf (dmCfg.enable && dmCfg.provider == "lemurs") {
    environment.systemPackages = [pkgs.lemurs];

    environment.etc."lemurs/config.toml".source = configFile;

    # /etc/lemurs/wayland/<defaultSession> にリンクを貼っておくと、
    # lemurs の Wayland 環境メニューに直接デフォルトセッションが出現します
    environment.etc."lemurs/wayland/${dmCfg.defaultSession}" = {
      source = pkgs.writeShellScript "lemurs-${dmCfg.defaultSession}" ''
        exec ${dmCfg.sessionWrapper} "${dmCfg.defaultSession}"
      '';
      mode = "0755";
    };

    # キャッシュや一時作業用ディレクトリ
    system.stateDirectories = [
      {
        path = "/etc/lemurs/wms";
        mode = "0755";
      }
      {
        path = "/etc/lemurs/wayland";
        mode = "0755";
      }
      {
        path = "/var/cache/lemurs";
        mode = "0755";
      }
    ];

    system.s6-rc.services.lemurs = {
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
        ${pkgs.lemurs}/bin/lemurs --config ${configFile}
      '';
    };
  };
}
