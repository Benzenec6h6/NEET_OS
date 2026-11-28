{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  sysPolkitCfg = config.neet.security.polkit;
  sysAgentCfg = config.neet.security.polkit.hyprpolkitagent;

  anyUserEnabled = any (u: u.security.polkit.hyprpolkitagent.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── システム共通設定 ───
    neet.security.polkit.hyprpolkitagent = {
      package = mkOption {
        type = types.package;
        default = pkgs.hyprpolkitagent;
        description = "使用する hyprpolkitagent パッケージ";
      };
    };

    # ─── ユーザーごとの設定・s6 サービス ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.security.polkit.hyprpolkitagent;
      in {
        options.security.polkit.hyprpolkitagent = {
          enable = mkOption {
            type = types.bool;
            # システムで Polkit が有効 かつ デフォルトが hyprpolkitagent かつ セッションユーザーなら true
            default = sysPolkitCfg.enable && (sysPolkitCfg.agent == "hyprpolkitagent") && config.isSessionUser;
            description = "ユーザー '${name}' で hyprpolkitagent 認証エージェントを有効にするか";
          };

          package = mkOption {
            type = types.package;
            default = sysAgentCfg.package;
            description = "ユーザー '${name}' が使用する hyprpolkitagent パッケージ";
          };
        };

        config = mkIf userCfg.enable {
          # ★ 方針A: s6.services.hyprpolkitagent に登録
          s6.services.hyprpolkitagent = {
            type = "longrun";
            autoStart = false;
            partOf = ["graphical-session"];
            run = ''
              #!${pkgs.runtimeShell}
              exec ${pkgs.s6}/bin/s6-envdir -I "$XDG_RUNTIME_DIR/env" ${userCfg.package}/libexec/hyprpolkitagent
            '';
          };
        };
      }));
    };
  };

  config = mkIf (sysPolkitCfg.enable && anyUserEnabled) {
    environment.systemPackages = [sysAgentCfg.package];
  };
}
