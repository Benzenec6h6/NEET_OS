{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.hyprland;

  libinput = config.services.deviceManagerLibinput;
  udevApi = config.services.deviceManagerUdevApi;

  aquamarine = pkgs.aquamarine.override (optionalAttrs (udevApi != null) {
    inherit libinput;
    udev = udevApi;
  });

  hyprlandPackage = pkgs.hyprland.override {
    inherit aquamarine libinput;
    withSystemd = udevApi == null;
  };

  # greetd から叩かれる .desktop ファイル
  # ※ 前回の分析通り、dbus-run-session は使わず、
  # s6-rc で動いている $XDG_RUNTIME_DIR/bus を直接見に行かせます
  sessionFile = pkgs.writeTextDir "share/wayland-sessions/hyprland.desktop" ''
    [Desktop Entry]
    Name=Hyprland
    Comment=Dynamic tiling Wayland compositor
    Exec=env DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus ${lib.getExe hyprlandPackage}
    Type=Application
    DesktopNames=Hyprland
  '';
in {
  options.programs.hyprland = {
    enable = mkEnableOption "Hyprland Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = "Hyprland 設定ファイル (hyprland.conf) のパス";
    };

    package = mkOption {
      type = types.package;
      default = hyprlandPackage;
      description = "使用する Hyprland パッケージ";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      (lib.hiPrio sessionFile)
    ];

    # seatd の有効化と設定配置
    services.seatd.enable = mkDefault true;
    environment.etc."hypr/hyprland.conf".source = cfg.configFile;

    environment.variables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };
  };
}
