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

  # ユーザーの Lua 設定を dofile() し、起動完了通知フックを足したラッパー設定。
  # ~/.config 側が優先されないよう --config で明示的に渡す。
  wrapperConfig = pkgs.writeText "hyprland.lua" ''
    -- 1. ユーザー設定の読み込み (Nix ストア上の lua スクリプトを実行)
    dofile("${cfg.configFile}")

    -- 2. NEET_OS: 起動完了通知フック (s6-rc の graphical-session を起動)
    hl.exec_cmd("${getExe config.services.displayManager.sessionReady} HYPRLAND_INSTANCE_SIGNATURE")

    -- 3. NEET_OS: シャットダウンフック (Wayland が閉じる前に graphical-session を停止)
    hl.on("hyprland.shutdown", function()
      local live_dir = os.getenv("S6_LIVE_DIR")
      if live_dir then
        -- graphical-session をダウンさせ、ソケット切断によるクラッシュを防ぐ
        os.execute("${pkgs.s6-rc}/bin/s6-rc -l " .. live_dir .. " -d change graphical-session")
      end
    end)

    -- 4. 追加 Lua 設定
    ${cfg.extraConfig}
  '';
in {
  options.programs.hyprland = {
    enable = mkEnableOption "Hyprland Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = ''
        Hyprland 設定ファイル (hyprland.lua) のパス。
        NEET_OS が生成するラッパー設定から `dofile()` で読み込まれます。
        設定内で他ファイルを相対参照する場合は、flake 利用時のみ期待通り動作します。
      '';
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "ラッパー設定 (hyprland.lua) の末尾に連結される追加 Lua コード";
    };

    package = mkOption {
      type = types.package;
      default = hyprlandPackage;
      description = "使用する Hyprland パッケージ";
    };
  };

  config = mkIf cfg.enable {
    neet.windowManager.active = ["hyprland"];
    xdg.portal = {
      enable = mkDefault true;
      portals = [
        pkgs.xdg-desktop-portal-hyprland
        pkgs.xdg-desktop-portal-gtk
      ];
      config.hyprland = {
        default = ["hyprland" "gtk"];
      };
    };

    services.displayManager.sessions.hyprland = {
      command = "${cfg.package}/bin/start-hyprland --path ${getExe cfg.package} -- --config ${wrapperConfig}";
      displayName = "Hyprland";
      comment = "Dynamic tiling Wayland compositor";
      desktopNames = ["Hyprland"];
    };

    environment.systemPackages = [cfg.package pkgs.qt6.qtwayland];
    environment.etc."hypr/hyprland.lua".source = wrapperConfig;
  };
}
