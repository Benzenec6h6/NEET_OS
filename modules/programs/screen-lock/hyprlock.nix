{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.screen-lock.hyprlock;
  sysConfig = config;

  anyUserEnabled = any (u: u.programs.screen-lock.hyprlock.enable) (attrValues config.neet.users);
  isEnabled = cfg.enable || anyUserEnabled;
in {
  options = {
    # ─── システム全体の設定（PAM・パッケージ・システム共通フォールバック） ───
    neet.programs.screen-lock.hyprlock = {
      enable = mkEnableOption "hyprlock (Wayland screen locker)";

      package = mkOption {
        type = types.package;
        default = pkgs.hyprlock;
        description = "使用する hyprlock パッケージ";
      };

      defaultConfig = mkOption {
        type = types.lines;
        default = ''
          background {
              monitor =
              color = rgba(25, 20, 20, 1.0)
          }
          input-field {
              monitor =
              size = 200, 50
              outline_thickness = 3
              dots_size = 0.33
              dots_spacing = 0.15
              fade_on_empty = false
          }
        '';
        description = "ユーザー設定がない場合に /etc/hypr/hyprlock.conf として使われるデフォルト設定";
      };
    };

    # ─── ユーザーごとの設定 ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.screen-lock.hyprlock;
        hasConfigFile = userCfg.configFile != null;
        hasExtraConfig = userCfg.extraConfig != "";
        hasConfig = hasConfigFile || hasExtraConfig;

        targetConfig =
          if hasConfigFile
          then userCfg.configFile
          else pkgs.writeText "hyprlock-${name}.conf" userCfg.extraConfig;
      in {
        options.programs.screen-lock.hyprlock = {
          enable = mkOption {
            type = types.bool;
            # システムで有効、かつ sessionUsers ならデフォルトで利用可能
            default = cfg.enable && (hasAttr name sysConfig.neet.sessionUsers);
            description = "ユーザー '${name}' で hyprlock を有効化するか";
          };

          configFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "外部の hyprlock.conf ファイルパス";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "インラインで書くユーザー固有の hyprlock 設定";
          };
        };

        config = mkIf (userCfg.enable && hasConfig) {
          assertions = [
            {
              assertion = !(hasConfigFile && hasExtraConfig);
              message = "neet.users.${name}.programs.screen-lock.hyprlock: `configFile` と `extraConfig` を両方指定することはできません。";
            }
          ];

          # ★ ユーザーの ~/.config/hypr/hyprlock.conf に配置
          xdg.configFile."hypr/hyprlock.conf".source = targetConfig;
        };
      }));
    };
  };

  config = mkIf isEnabled {
    environment.systemPackages = [cfg.package];

    # PAM 認証の登録 (これがないとロック解除不可)
    neet.security.pam.services.hyprlock = {};

    # ユーザー設定がない場合のフォールバック用
    environment.etc."hypr/hyprlock.conf" = mkIf (cfg.defaultConfig != "") {
      text = cfg.defaultConfig;
    };
  };
}
