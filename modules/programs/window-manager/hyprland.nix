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

  # ユーザー設定を source し、起動完了通知フックを足したラッパー設定。
  # ~/.config 側が優先されないよう --config で明示的に渡す。
  wrapperConfig = pkgs.writeText "hyprland.conf" ''
    source = ${cfg.configFile}
    exec-once = ${getExe config.services.displayManager.sessionReady} HYPRLAND_INSTANCE_SIGNATURE
    ${cfg.extraConfig}
  '';
in {
  options.programs.hyprland = {
    enable = mkEnableOption "Hyprland Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = ''
        Hyprland 設定ファイル (hyprland.conf) のパス。
        NEET_OS が生成するラッパー設定から `source` されます。
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
      default = hyprlandPackage;
      description = "使用する Hyprland パッケージ";
    };
  };

  config = mkIf cfg.enable {
    services.displayManager.sessions.hyprland = {
      command = "${getExe cfg.package} --config ${wrapperConfig}";
      displayName = "Hyprland";
      comment = "Dynamic tiling Wayland compositor";
      desktopNames = ["Hyprland"];
    };

    environment.systemPackages = [cfg.package];
    environment.etc."hypr/hyprland.conf".source = wrapperConfig;
  };
}
