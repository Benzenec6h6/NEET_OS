{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  sysCfg = config.neet.programs.idle.hypridle;

  anyUserEnabled = any (u: u.programs.idle.hypridle.enable) (attrValues config.neet.users);
in {
  options = {
    neet.programs.idle.hypridle = {
      package = mkOption {
        type = types.package;
        default = pkgs.hypridle;
        description = "使用する hypridle パッケージ";
      };
    };

    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.idle.hypridle;
        hasConfigFile = userCfg.configFile != null;
        hasExtraConfig = userCfg.extraConfig != "";
        hasConfig = hasConfigFile || hasExtraConfig;

        targetConfig =
          if hasConfigFile
          then userCfg.configFile
          else pkgs.writeText "hypridle-${name}.conf" userCfg.extraConfig;
      in {
        options.programs.idle.hypridle = {
          enable = mkEnableOption "hypridle for user '${name}'";

          configFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            example = literalExpression "./hypridle.conf";
            description = "外部の hypridle.conf ファイルパス（extraConfig とは排他）";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "インラインで設定を書く場合の内容（configFile とは排他）";
          };
        };

        config = mkIf userCfg.enable {
          assertions = [
            {
              assertion = !(hasConfigFile && hasExtraConfig);
              message = "neet.users.${name}.programs.idle.hypridle: `configFile` と `extraConfig` を両方指定することはできません。";
            }
          ];

          xdg.configFile."hypr/hypridle.conf" = mkIf hasConfig {
            source = targetConfig;
          };

          # ★ s6.services に定義
          s6.services.hypridle = {
            type = "longrun";
            partOf = ["graphical-session"];
            log.enable = true;
            run = ''
              #!/bin/sh
              exec ${sysCfg.package}/bin/hypridle
            '';
          };
        };
      }));
    };
  };

  config = mkIf anyUserEnabled {
    environment.systemPackages = [sysCfg.package];
  };
}
