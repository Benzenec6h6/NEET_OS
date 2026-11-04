{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.sway;
  libinput = config.services.deviceManagerLibinput;
  isNonSystemd = config.services.deviceManagerUdevApi != null;

  sway-unwrapped = pkgs.sway-unwrapped.override (o: let
    wlrootsAttr = head (filter (hasPrefix "wlroots") (attrNames o));
  in {
    inherit libinput;
    ${wlrootsAttr} = o.${wlrootsAttr}.override {inherit libinput;};
    systemdSupport = !isNonSystemd;
  });

  swayPackage = pkgs.sway.override {
    inherit sway-unwrapped;
  };

  sessionFile = pkgs.writeTextDir "share/wayland-sessions/sway.desktop" ''
    [Desktop Entry]
    Name=Sway
    Comment=An i3-compatible Wayland compositor
    Exec=env DBUS_SESSION_BUS_ADDRESS=unix:path=%t/bus ${lib.getExe swayPackage}
    Type=Application
    DesktopNames=sway;wlroots
  '';
in {
  options.programs.sway = {
    enable = mkEnableOption "Sway Wayland compositor";
    configFile = mkOption {
      type = types.path;
      description = "Sway 設定ファイル (sway.conf) のパス";
    };
    package = mkOption {
      type = types.package;
      default = swayPackage;
      description = "使用する Sway パッケージ";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
      (lib.hiPrio sessionFile)
    ];

    services.seatd.enable = mkDefault true;
    environment.etc."sway/config".source = cfg.configFile;
    environment.variables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };
  };
}
