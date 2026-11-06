{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  polkitCfg = config.neet.security.polkit;
  cfg = config.neet.security.polkit.cmdPolkit;
  enableAgent = polkitCfg.enable && (polkitCfg.agent == "cmd-polkit");

  # extraPackages からこのサービス専用のローカル PATH を構築
  servicePath = makeBinPath cfg.extraPackages;

  cmdPolkitService = {
    type = "longrun";
    autoStart = false;
    partOf = ["graphical-session"];

    run = ''
      #!${pkgs.runtimeShell}
      ${optionalString (cfg.extraPackages != []) ''
        export PATH="${servicePath}:$PATH"
      ''}
      exec ${pkgs.s6}/bin/s6-envdir -I "$XDG_RUNTIME_DIR/env" \
        ${getExe pkgs.cmd-polkit} -s -c ${escapeShellArg cfg.command}
    '';
  };
in {
  options.neet.security.polkit.cmdPolkit = {
    command = mkOption {
      type = types.str;
      example = "fuzzel --dmenu --password";
      description = "cmd-polkit がパスワードを尋ねる際に実行するコマンドライン";
    };

    extraPackages = mkOption {
      type = types.listOf types.package;
      default = [];
      example = literalExpression "[ pkgs.fuzzel ]";
      description = ''
        command の実行に必要なパッケージ一覧。
        システム全体 (systemPackages) を汚染せず、この認証エージェントの
        プロセス内でのみ有効な PATH として安全に注入されます。
      '';
    };
  };

  config = mkIf enableAgent {
    # cmd-polkit 本体のみ（extraPackages は s6 スクリプトのローカル PATH に閉じる）
    environment.systemPackages = [pkgs.cmd-polkit];

    system.s6-rc.users =
      mapAttrs (_username: _user: {
        services.cmd-polkit = cmdPolkitService;
      })
      config.system.s6-rc.users;
  };
}
