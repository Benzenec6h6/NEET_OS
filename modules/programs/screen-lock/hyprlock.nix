{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.screen-lock.hyprlock;
in {
  options.neet.programs.screen-lock.hyprlock = {
    enable = mkEnableOption "hyprlock (Wayland screen locker)";

    package = mkOption {
      type = types.package;
      default = pkgs.hyprlock;
      description = "使用する hyprlock パッケージ";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "./hyprlock.conf";
      description = "外部の hyprlock.conf ファイルパス（指定時は /etc/hypr/hyprlock.conf に配置されます）";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = ''
        # 最低限のデフォルト設定 (ユーザーの ~/.config/hypr/hyprlock.conf が優先されます)
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
      description = "/etc/hypr/hyprlock.conf に配置するシステムデフォルト設定";
    };
  };

  config = mkIf cfg.enable {
    # 1. パッケージのインストール
    environment.systemPackages = [cfg.package];

    # 2. PAM サービスの登録 (/etc/pam.d/hyprlock が生成される)
    neet.security.pam.services.hyprlock = {};

    # 3. システムレベルのデフォルト設定ファイル配置
    environment.etc."hypr/hyprlock.conf" = mkIf (cfg.extraConfig != "") {
      text = cfg.extraConfig;
    };
  };
}
