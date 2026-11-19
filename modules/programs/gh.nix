{
  config,
  lib,
  pkgs,
  ...
}: let
  inherit
    (lib)
    literalExpression
    mkEnableOption
    mkIf
    mkOption
    mkPackageOption
    types
    ;

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

  # extensions が指定されている場合、起動時に ~/.local/share/gh/extensions にリンクを張るラッパー
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
in {
  options.programs.gh = {
    enable = mkEnableOption "GitHub CLI tool";

    package = mkPackageOption pkgs "gh" {};

    settings = mkOption {
      type = settingsType;
      default = {};
      description = ''
        Global configuration for gh.
        Written to /etc/xdg/gh/config.yml (as default template) or user config.
      '';
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
        description = "GitHub hosts to enable the gh git credential helper for.";
        example = literalExpression ''
          [ "https://github.com" "https://github.example.com" ]
        '';
      };
    };

    extensions = mkOption {
      type = types.listOf types.package;
      default = [];
      description = ''
        List of gh extensions to install globally (e.g. pkgs.gh-dash, pkgs.gh-eco).
      '';
      example = literalExpression "[ pkgs.gh-dash ]";
    };
  };

  config = mkIf cfg.enable {
    # ラップされた gh パッケージをシステムにインストール
    environment.systemPackages = [finalPackage];

    # システム共通のデフォルト設定テンプレート (/etc/xdg/gh/config.yml)
    environment.etc."xdg/gh/config.yml" = mkIf (cfg.settings != {}) {
      source = yamlFormat.generate "gh-config.yml" ({version = "1";} // cfg.settings);
    };

    # Git のシステム全体設定 (/etc/gitconfig) に Credential Helper を登録
    # ※ NEET_OS に programs.git がある場合はそちらに渡す形に変更可能
    environment.etc."gitconfig" = mkIf cfg.gitCredentialHelper.enable {
      text = lib.concatStringsSep "\n" (
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
