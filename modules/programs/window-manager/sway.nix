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

  swayPackage = pkgs.sway.override {inherit sway-unwrapped;};

  wrapperConfig = pkgs.writeText "sway-config" ''
    include ${cfg.configFile}
    exec ${getExe config.services.displayManager.sessionReady} SWAYSOCK
    ${cfg.extraConfig}
  '';

  swaySession = pkgs.writeShellScript "sway-session" ''
    status=0
    cleanup() {
      trap - EXIT INT TERM
      if [ -n "$S6_LIVE_DIR" ]; then
        ${pkgs.s6-rc}/bin/s6-rc -l "$S6_LIVE_DIR" -d change graphical-session
      fi
      exit "$status"
    }
    trap cleanup EXIT INT TERM

    ${getExe cfg.package} --config ${wrapperConfig}
    status=$?
  '';
in {
  options.programs.sway = {
    enable = mkEnableOption "Sway Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = ''
        Sway 設定ファイルのパス。NEET_OS が生成するラッパー設定から `include` されます。
        設定内で他ファイルを相対参照する場合は、flake 利用時のみ期待通り動作します。
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "ラッパー設定の末尾に連結される追加設定";
    };

    package = mkOption {
      type = types.package;
      default = swayPackage;
      description = "使用する Sway パッケージ";
    };
  };

  config = mkIf cfg.enable {
    neet.windowManager.active = ["sway"];
    xdg.portal = {
      enable = mkDefault true;
      portals = [
        pkgs.xdg-desktop-portal-wlr
        pkgs.xdg-desktop-portal-gtk
      ];
      config.sway = {
        default = ["wlr" "gtk"];
      };
    };

    services.displayManager.sessions.sway = {
      # 作成したラッパースクリプトを指定する
      command = "${swaySession}";
      displayName = "Sway";
      comment = "An i3-compatible Wayland compositor";
      desktopNames = ["sway" "wlroots"];
    };

    # swaySession は直接パスで呼ばれるため systemPackages には含めなくて OK
    environment.systemPackages = [cfg.package];
    environment.etc."sway/config".source = wrapperConfig;
  };
}
