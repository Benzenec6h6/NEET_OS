{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  polkitCfg = config.neet.security.polkit;
  cfg = config.neet.security.polkit.hyprpolkitagent;
  enableAgent = polkitCfg.enable && (polkitCfg.agent == "hyprpolkitagent");

  # s6-rc サービス定義
  hyprpolkitagentService = {
    type = "longrun";
    # top バンドル (ログイン直後) には入れず、graphical-session に所属させる
    autoStart = false;
    partOf = ["graphical-session"];

    # 起動スクリプト: sessionReady が書き出した環境変数を読み込んで起動
    # s6-envdir で $XDG_RUNTIME_DIR/env を取り込んでからバイナリを実行する
    run = ''
      #!${pkgs.runtimeShell}
      exec ${pkgs.s6}/bin/s6-envdir -I "$XDG_RUNTIME_DIR/env" ${cfg.package}/libexec/hyprpolkitagent
    '';
  };
in {
  options.neet.security.polkit.hyprpolkitagent = {
    package = mkOption {
      type = types.package;
      default = pkgs.hyprpolkitagent;
      description = "使用する hyprpolkitagent パッケージ";
    };
  };

  config = mkIf enableAgent {
    environment.systemPackages = [cfg.package];

    # 定義されている全ユーザーの s6-rc に hyprpolkitagent を注入する
    system.s6-rc.users =
      mapAttrs (_username: _user: {
        services.hyprpolkitagent = hyprpolkitagentService;
      })
      config.neet.sessionUsers;
  };
}
