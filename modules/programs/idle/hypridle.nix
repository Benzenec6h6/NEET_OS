{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.idle.hypridle;

  hasConfigFile = cfg.configFile != null;
  hasExtraConfig = cfg.extraConfig != "";
  hasConfig = hasConfigFile || hasExtraConfig;

  targetConfig =
    if hasConfigFile
    then cfg.configFile
    else pkgs.writeText "hypridle.conf" cfg.extraConfig;
in {
  options.neet.programs.idle.hypridle = {
    enable = lib.mkEnableOption "hypridle (Wayland idle daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.hypridle;
      description = "使用する hypridle パッケージ";
    };

    configFile = lib.mkOption {
      type = lib.types.nullOr lib.types.path;
      default = null;
      example = literalExpression "./hypridle.conf";
      description = "外部の hypridle.conf ファイルパス（extraConfig とは排他）";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      example = ''
        listener {
            timeout = 300
            on-timeout = hyprlock
        }
      '';
      description = "インラインで設定を書く場合の内容（configFile とは排他）";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = !(hasConfigFile && hasExtraConfig);
        message = "neet.programs.idle.hypridle: `configFile` と `extraConfig` を両方指定することはできません。";
      }
    ];

    environment.systemPackages = [cfg.package];

    # 設定が指定されている場合のみ /etc/hypr/hypridle.conf を生成
    # (未指定の場合はユーザーの ~/.config/hypr/hypridle.conf が使われます)
    environment.etc."hypr/hypridle.conf" = lib.mkIf hasConfig {
      source = targetConfig;
    };

    # s6-rc ユーザーサービス登録
    system.s6-rc.users =
      lib.mapAttrs (name: u: {
        services.hypridle = {
          type = "longrun";
          partOf = ["graphical-session"];
          run = ''
            #!/bin/sh
            exec ${cfg.package}/bin/hypridle
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
