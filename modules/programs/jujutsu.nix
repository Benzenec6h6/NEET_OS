{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.programs.jujutsu;
  tomlFormat = pkgs.formats.toml {};

  # システム共通設定の構築
  systemUserConfig = filterAttrs (_: v: v != null) {
    name = cfg.userName;
    email = cfg.userEmail;
  };

  systemFinalConfig =
    recursiveUpdate
    (optionalAttrs (systemUserConfig != {}) {user = systemUserConfig;})
    cfg.settings;

  anyUserEnabled = cfg.enable || any (u: u.programs.jujutsu.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── システム共通設定 ───
    programs.jujutsu = {
      enable = mkEnableOption "Jujutsu (jj) version control system";

      package = mkPackageOption pkgs "jujutsu" {};

      userName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "システム共通のデフォルトコミットユーザー名";
      };

      userEmail = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "システム共通のデフォルトコミットメールアドレス";
      };

      enableDynamicCompletion = mkOption {
        type = types.bool;
        default = false;
        description = "対話的シェルで jujutsu の動的補完（ブランチやリビジョン）を有効にするか";
      };

      settings = mkOption {
        type = tomlFormat.type;
        default = {};
        description = "システム共通の jj 設定 (/etc/jj/config.toml)";
      };
    };

    # ─── ユーザーごとの設定 ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.jujutsu;

        userIdentConfig = filterAttrs (_: v: v != null) {
          name = userCfg.userName;
          email = userCfg.userEmail;
        };

        userFinalConfig =
          recursiveUpdate
          (optionalAttrs (userIdentConfig != {}) {user = userIdentConfig;})
          userCfg.settings;
      in {
        options.programs.jujutsu = {
          enable = mkOption {
            type = types.bool;
            default = cfg.enable && config.isSessionUser;
            description = "ユーザー '${name}' で jujutsu 設定を有効にするか";
          };

          userName = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "ユーザー '${name}' のコミット用名前";
          };

          userEmail = mkOption {
            type = types.nullOr types.str;
            default = null;
            description = "ユーザー '${name}' のコミット用メールアドレス";
          };

          settings = mkOption {
            type = tomlFormat.type;
            default = {};
            description = "ユーザー固有の jj 設定 (~/.config/jj/config.toml)";
          };
        };

        config = mkIf userCfg.enable {
          xdg.configFile."jj/config.toml" = mkIf (userFinalConfig != {}) {
            source = tomlFormat.generate "jj-user-config.toml" userFinalConfig;
          };
        };
      }));
    };
  };

  config = mkIf anyUserEnabled {
    environment.systemPackages = [cfg.package];

    # システム共通設定 (/etc/jj/config.toml)
    environment.etc."jj/config.toml" = mkIf (systemFinalConfig != {}) {
      source = tomlFormat.generate "jj-config.toml" systemFinalConfig;
    };

    # シェル補完設定
    programs.bash.interactiveShellInit = mkIf (config.programs.bash.enable && cfg.enableDynamicCompletion) ''
      # jujutsu dynamic completion
      source <(COMPLETE=bash ${getExe cfg.package})
    '';

    programs.zsh.interactiveShellInit = mkIf (config.programs.zsh.enable && cfg.enableDynamicCompletion) ''
      # jujutsu dynamic completion
      source <(COMPLETE=zsh ${getExe cfg.package})
    '';
  };
}
