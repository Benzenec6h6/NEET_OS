{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.sway;
  runtimeUsers = filterAttrs (_name: u: u.createRuntimeDir && u.uid >= 1000) config.neet.users;
in {
  options.programs.sway = {
    enable = mkEnableOption "Sway Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = "Sway 設定ファイル (sway.conf) のパス";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.sway];

    services.seatd.enable = mkDefault true;
    environment.etc."sway/config".source = cfg.configFile;
    environment.variables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };

    # ユーザー s6-rc に登録するが、勝手には起動させない (autoStart = false)
    system.s6-rc.users =
      mapAttrs (name: u: {
        services.sway = {
          type = "longrun";
          autoStart = false;
          dependencies = ["dbus"];
          restartOnUpdate = false;
          run = ''
            #!/bin/sh
            ${pkgs.sway}/bin/sway
            ${pkgs.s6}/bin/s6-svscanctl -t "$XDG_RUNTIME_DIR/service"
          '';
        };
      })
      runtimeUsers;

    # DM は引数 "sway" を付けてセッションランナーを呼ぶ
    environment.etc."wayland-sessions/sway.desktop".text = ''
      [Desktop Entry]
      Name=Sway
      Comment=An i3-compatible Wayland compositor
      Exec=${config.services.displayManager.sessionWrapper} sway
      Type=Application
    '';
  };
}
