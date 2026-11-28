{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  sysPolkitCfg = config.neet.security.polkit;

  anyUserEnabled = any (u: u.security.polkit.cmdPolkit.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── ユーザーごとの設定・s6 サービス ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.security.polkit.cmdPolkit;
        servicePath = makeBinPath userCfg.extraPackages;
      in {
        options.security.polkit.cmdPolkit = {
          enable = mkOption {
            type = types.bool;
            # システムで Polkit が有効 かつ デフォルトが cmd-polkit かつ セッションユーザーなら true
            default = sysPolkitCfg.enable && (sysPolkitCfg.agent == "cmd-polkit") && config.isSessionUser;
            description = "ユーザー '${name}' で cmd-polkit 認証エージェントを有効にするか";
          };

          command = mkOption {
            type = types.str;
            default = "fuzzel --dmenu --password";
            example = "fuzzel --dmenu --password";
            description = "ユーザー '${name}' がパスワードを尋ねる際に実行するコマンドライン";
          };

          extraPackages = mkOption {
            type = types.listOf types.package;
            default = [];
            example = literalExpression "[ pkgs.fuzzel ]";
            description = "command の実行に必要なパッケージ一覧（このサービスの PATH にのみ安全に注入）";
          };
        };

        config = mkIf userCfg.enable {
          s6.services.cmd-polkit = {
            type = "longrun";
            autoStart = false;
            partOf = ["graphical-session"];
            run = ''
              #!${pkgs.runtimeShell}
              ${optionalString (userCfg.extraPackages != []) ''
                export PATH="${servicePath}:$PATH"
              ''}
              exec ${pkgs.s6}/bin/s6-envdir -I "$XDG_RUNTIME_DIR/env" \
                ${getExe pkgs.cmd-polkit} -s -c ${escapeShellArg userCfg.command}
            '';
          };
        };
      }));
    };
  };

  config = mkIf (sysPolkitCfg.enable && anyUserEnabled) {
    # 誰か1人でも使っていればシステムにパッケージをインストール
    environment.systemPackages = [pkgs.cmd-polkit];
  };
}
