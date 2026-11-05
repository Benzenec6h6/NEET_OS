{
  config,
  lib,
  ...
}:
with lib; let
  wmEnabled = config.programs.hyprland.enable || config.programs.sway.enable;
in {
  imports = [
    ./hyprland.nix
    ./sway.nix
  ];

  # 方針: X11セッションは非サポート。必要ならXWaylandを使うこと。
  config = mkIf wmEnabled {
    services.seatd.enable = mkDefault true;
    environment.variables.WLR_NO_HARDWARE_CURSORS = "1";
  };
}
