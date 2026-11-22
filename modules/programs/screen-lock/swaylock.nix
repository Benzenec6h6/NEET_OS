{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.screen-lock.swaylock;
  sysConfig = config;

  anyUserEnabled = any (u: u.programs.screen-lock.swaylock.enable) (attrValues config.neet.users);
  isEnabled = cfg.enable || anyUserEnabled;
in {
  options = {
    # ─── システム全体の設定 ───
    neet.programs.screen-lock.swaylock = {
      enable = mkEnableOption "swaylock (Wayland screen locker)";

      package = mkOption {
        type = types.package;
        default = pkgs.swaylock-effects;
        description = "使用する swaylock パッケージ";
      };

      defaultConfig = mkOption {
        type = types.lines;
        default = "";
        description = "ユーザー設定がない場合に /etc/swaylock/config として使われるデフォルト設定";
      };
    };

    # ─── ユーザーごとの設定 ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.screen-lock.swaylock;
        hasConfigFile = userCfg.configFile != null;
        hasExtraConfig = userCfg.extraConfig != "";
        hasConfig = hasConfigFile || hasExtraConfig;

        targetConfig =
          if hasConfigFile
          then userCfg.configFile
          else pkgs.writeText "swaylock-${name}.conf" userCfg.extraConfig;
      in {
        options.programs.screen-lock.swaylock = {
          enable = mkOption {
            type = types.bool;
            default = cfg.enable && (hasAttr name sysConfig.neet.sessionUsers);
            description = "ユーザー '${name}' で swaylock を有効化するか";
          };

          configFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "外部の swaylock 設定ファイルパス";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "インラインで書くユーザー固有の swaylock 設定";
          };
        };

        config = mkIf (userCfg.enable && hasConfig) {
          assertions = [
            {
              assertion = !(hasConfigFile && hasExtraConfig);
              message = "neet.users.${name}.programs.screen-lock.swaylock: `configFile` と `extraConfig` を両方指定することはできません。";
            }
          ];

          # ★ ユーザーの ~/.config/swaylock/config に配置
          xdg.configFile."swaylock/config".source = targetConfig;
        };
      }));
    };
  };

  config = mkIf isEnabled {
    # ラッパーを使わず生パッケージを導入（ツール本来の ~/.config 優先探索を活かす）
    environment.systemPackages = [cfg.package];

    # PAM 認証の登録
    neet.security.pam.services.swaylock = {};

    # ユーザー設定がない場合のフォールバック用
    environment.etc."swaylock/config" = mkIf (cfg.defaultConfig != "") {
      text = cfg.defaultConfig;
    };
  };
}
