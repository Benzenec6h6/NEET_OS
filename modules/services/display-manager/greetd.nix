{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;

  # tuigreet のコマンドライン
  # env で greeter 用の XDG_RUNTIME_DIR を明示的に設定して起動する
  tuigreetCmd = concatStringsSep " " [
    "${pkgs.coreutils}/bin/env"
    "XDG_RUNTIME_DIR=/run/user/970"
    "${pkgs.tuigreet}/bin/tuigreet"
    "--debug"
    "--time"
    "--remember"
    "--remember-session"
    "--sessions /etc/wayland-sessions"
    "--session-wrapper ${dmCfg.sessionWrapper}"
    (optionalString (dmCfg.defaultSession != "") "--cmd ${dmCfg.defaultSession}")
  ];

  greetdConfig = pkgs.writeText "greetd.toml" ''
    [terminal]
    vt = ${toString dmCfg.tty}

    [default_session]
    command = "${tuigreetCmd}"
    user = "greeter"
  '';
in {
  config = mkIf (dmCfg.enable && dmCfg.provider == "greetd") {
    environment.systemPackages = [
      pkgs.greetd
      pkgs.tuigreet
    ];

    # greeter ユーザーの定義
    neet.users.greeter = {
      uid = mkDefault 970;
      gid = mkDefault 970;
      description = "greetd greeter user";
      home = "/var/lib/greetd";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = true;
      createRuntimeDir = true;

      # ★ 描画・入力デバイスにアクセスするためのグループを追加
      extraGroups =
        [
          "video"
          "input"
        ]
        ++ optional config.services.seatd.enable "seat";
    };

    # 必要なステートディレクトリの準備
    system.stateDirectories = [
      {
        path = "/var/lib/greetd";
        mode = "0750";
        user = "greeter";
        group = "greeter";
      }
      # ★ tuigreet の --remember 用キャッシュディレクトリ
      {
        path = "/var/cache/tuigreet";
        mode = "0755";
        user = "greeter";
        group = "greeter";
      }
      # greeter 用の XDG_RUNTIME_DIR (UID: 970)
      {
        path = "/run/user/970";
        mode = "0700";
        user = "greeter";
        group = "greeter";
      }
    ];

    system.s6-rc.services.greetd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.services.seatd.enable "seatd"
        ++ optional config.services.sessiond.enable "sessiond";

      log.enable = true;

      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        ${pkgs.greetd}/bin/greetd --config ${greetdConfig}
      '';
    };
  };
}
