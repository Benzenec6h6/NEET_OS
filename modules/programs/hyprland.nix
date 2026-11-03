{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.hyprland;
in {
  options.programs.hyprland = {
    enable = mkEnableOption "Hyprland Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = "Hyprland 設定ファイル (hyprland.conf) のパス";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.hyprland];

    services.seatd.enable = mkDefault true;
    environment.etc."hypr/hyprland.conf".source = cfg.configFile;
    environment.variables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };

    # 勝手には起動させない
    system.s6-rc.users =
      mapAttrs (name: u: {
        services.hyprland = {
          type = "longrun";
          autoStart = false;
          dependencies = ["dbus"];
          restartOnUpdate = false;
          run = ''
            #!/bin/sh
            ${pkgs.hyprland}/bin/Hyprland
            ${pkgs.s6}/bin/s6-svscanctl -t "$XDG_RUNTIME_DIR/service"
          '';
        };
      })
      config.neet.sessionUsers;

    # DM は引数 "hyprland" を付けて呼ぶ
    environment.etc."wayland-sessions/hyprland.desktop".text = ''
      [Desktop Entry]
      Name=Hyprland
      Comment=Dynamic tiling Wayland compositor
      Exec=hyprland
      Type=Application
    '';
  };
}
