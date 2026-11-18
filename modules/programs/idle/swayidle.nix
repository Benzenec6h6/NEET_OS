{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.idle.swayidle;
in {
  options.neet.programs.idle.swayidle = {
    enable = lib.mkEnableOption "swayidle (Wayland idle daemon)";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.swayidle;
      description = "使用する swayidle パッケージ";
    };

    args = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["-w"];
      example = [
        "-w"
        "timeout"
        "300"
        "swaylock -f"
        "timeout"
        "600"
        "hyprctl dispatch dpms off"
        "resume"
        "hyprctl dispatch dpms on"
        "before-sleep"
        "swaylock -f"
      ];
      description = "swayidle に渡すコマンドライン引数のリスト";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # s6-rc ユーザーサービス登録
    system.s6-rc.users =
      lib.mapAttrs (name: u: {
        services.swayidle = {
          type = "longrun";
          partOf = ["graphical-session"];
          run = ''
            #!/bin/sh
            exec ${cfg.package}/bin/swayidle ${lib.escapeShellArgs cfg.args}
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
