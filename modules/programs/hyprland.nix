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

    # 指定された設定ファイルを /etc/hypr/hyprland.conf として配置
    environment.etc."hypr/hyprland.conf".source = cfg.configFile;

    environment.sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };

    # DMが探索する Wayland セッションメタデータ
    environment.etc."wayland-sessions/hyprland.desktop".text = ''
      [Desktop Entry]
      Name=Hyprland
      Comment=Dynamic tiling Wayland compositor
      Exec=${pkgs.hyprland}/bin/Hyprland
      Type=Application
    '';
  };
}
