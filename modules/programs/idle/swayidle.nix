{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  sysCfg = config.neet.programs.idle.swayidle;

  anyUserEnabled = any (u: u.programs.idle.swayidle.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── システム共通設定 ───
    neet.programs.idle.swayidle = {
      package = mkOption {
        type = types.package;
        default = pkgs.swayidle;
        description = "使用する swayidle パッケージ";
      };
    };

    # ─── ユーザーごとの設定・s6 サービス ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.idle.swayidle;
      in {
        options.programs.idle.swayidle = {
          enable = mkEnableOption "swayidle for user '${name}'";

          args = mkOption {
            type = types.listOf types.str;
            default = ["-w"];
            example = [
              "-w"
              "timeout"
              "300"
              "swaylock -f"
              "before-sleep"
              "swaylock -f"
            ];
            description = "swayidle に渡すユーザー固有のコマンドライン引数リスト";
          };
        };

        config = mkIf userCfg.enable {
          # ★ s6.services.swayidle に変更
          s6.services.swayidle = {
            type = "longrun";
            partOf = ["graphical-session"];
            run = ''
              #!/bin/sh
              exec ${sysCfg.package}/bin/swayidle ${escapeShellArgs userCfg.args}
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
