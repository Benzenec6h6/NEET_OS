{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.gh;
  yamlFormat = pkgs.formats.yaml {};

  settingsType = types.submodule {
    freeformType = yamlFormat.type;
  };

  # 拡張機能をまとめた linkFarm
  extensionsEnv = pkgs.linkFarm "gh-extensions" (
    map (p: {
      name = p.pname or p.name;
      path = "${p}/bin";
    })
    cfg.extensions
  );

  finalPackage =
    if cfg.extensions == []
    then cfg.package
    else
      pkgs.symlinkJoin {
        name = "gh-wrapped-${cfg.package.version}";
        paths = [cfg.package];
        nativeBuildInputs = [pkgs.makeWrapper];
        postBuild = ''
          wrapProgram $out/bin/gh \
            --run '
              if [ -n "$HOME" ]; then
                extDir="$HOME/.local/share/gh/extensions"
                if [ ! -e "$extDir" ] || [ -L "$extDir" ]; then
                  mkdir -p "$HOME/.local/share/gh"
                  ln -sfn "${extensionsEnv}" "$extDir"
                fi
              fi
            '
        '';
      };

  anyUserEnabled = cfg.enable || any (u: u.programs.gh.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── システム共通設定 ───
    programs.gh = {
      enable = mkEnableOption "GitHub CLI tool";

      package = mkPackageOption pkgs "gh" {};

      settings = mkOption {
        type = settingsType;
        default = {};
        description = "システム共通の gh デフォルト設定 (/etc/xdg/gh/config.yml)";
        example = literalExpression ''
          {
            git_protocol = "ssh";
            prompt = "enabled";
            aliases = {
              co = "pr checkout";
              pv = "pr view";
            };
          }
        '';
      };

      gitCredentialHelper = {
        enable =
          mkEnableOption "the gh git credential helper"
          // {
            default = true;
          };

        hosts = mkOption {
          type = types.listOf types.str;
          default = [
            "https://github.com"
            "https://gist.github.com"
          ];
          description = "gh git credential helper を有効にするホスト一覧";
        };
      };

      extensions = mkOption {
        type = types.listOf types.package;
        default = [];
        description = "システム全体に導入する gh 拡張機能一覧";
      };
    };

    # ─── ユーザーごとの設定 ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.gh;
      in {
        options.programs.gh = {
          enable = mkOption {
            type = types.bool;
            default = cfg.enable && config.isSessionUser;
            description = "ユーザー '${name}' で gh を有効にするか";
          };

          settings = mkOption {
            type = settingsType;
            default = {};
            description = "ユーザー固有の gh 設定 (~/.config/gh/config.yml)";
          };
        };

        config = mkIf userCfg.enable {
          xdg.configFile."gh/config.yml" = mkIf (userCfg.settings != {}) {
            source = yamlFormat.generate "gh-user-config.yml" ({version = "1";} // userCfg.settings);
          };
        };
      }));
    };
  };

  config = mkIf anyUserEnabled {
    environment.systemPackages = [finalPackage];

    # システム全体のデフォルト設定フォールバック
    environment.etc."xdg/gh/config.yml" = mkIf (cfg.settings != {}) {
      source = yamlFormat.generate "gh-config.yml" ({version = "1";} // cfg.settings);
    };

    # Git Credential Helper の登録
    environment.etc."gitconfig" = mkIf cfg.gitCredentialHelper.enable {
      text = concatStringsSep "\n" (
        map (host: ''
          [credential "${host}"]
          	helper =
          	helper = !${cfg.package}/bin/gh auth git-credential
        '')
        cfg.gitCredentialHelper.hosts
      );
    };
  };
}
