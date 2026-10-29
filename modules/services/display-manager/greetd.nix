{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  dmCfg = config.services.displayManager;

  # greetd 設定ファイル (TOML)
  # フロントエンドには最も軽量で TTY 親和性の高い tuigreet を標準採用
  greetdConfig = pkgs.writeText "greetd.toml" ''
    [terminal]
    vt = ${toString dmCfg.tty}

    [default_session]
    command = "${pkgs.greetd.tuigreet}/bin/tuigreet --time --remember --cmd ${dmCfg.sessionWrapper}"
    user = "greeter"
  '';
in {
  config = mkIf (dmCfg.enable && dmCfg.provider == "greetd") {
    environment.systemPackages = [
      pkgs.greetd.greetd
      pkgs.greetd.tuigreet
    ];

    # greetd 用の専用無特権ユーザー
    neet.users.greeter = {
      uid = mkDefault 970;
      gid = mkDefault 970;
      description = "greetd greeter user";
      home = "/var/lib/greetd";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = true;
      createRuntimeDir = true;
    };

    # /var/log/greetd などのディレクトリ準備
    system.stateDirectories = [
      {
        path = "/var/lib/greetd";
        mode = "0750";
        user = "greeter";
        group = "greeter";
      }
    ];

    # s6-rc サービス定義
    system.s6-rc.services.greetd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.services.seatd.enable "seatd"
        ++ optional config.services.sessiond.enable "sessiond";

      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        ${pkgs.greetd.greetd}/bin/greetd --config ${greetdConfig}
      '';
    };
  };
}
