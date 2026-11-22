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

  # ★ ユーザー設定を動的に探索・読み込む共通ラッパー
  wrapperConfig = pkgs.writeText "hyprland-wrapper.lua" ''
    local user = os.getenv("USER") or ""
    local home = os.getenv("HOME") or ""

    -- 探索パス:
    -- 1. Nix 経由で生成されたユーザー設定 (/etc/users/<USER>/hypr/hyprland.lua)
    -- 2. ユーザーが手動で作成した設定 (~/.config/hypr/hyprland.lua)
    local nix_config = "/etc/users/" .. user .. "/hypr/hyprland.lua"
    local dot_config = home .. "/.config/hypr/hyprland.lua"

    local function file_exists(path)
      local f = io.open(path, "r")
      if f then f:close(); return true else return false end
    end

    -- 1. ユーザー設定の読み込み
    if file_exists(nix_config) then
      dofile(nix_config)
    elseif file_exists(dot_config) then
      dofile(dot_config)
    end

    -- 2. NEET_OS: 起動完了イベントで graphical-session を起動
    hl.on("hyprland.start", function()
      hl.exec_cmd("${getExe config.services.displayManager.sessionReady} HYPRLAND_INSTANCE_SIGNATURE")
    end)

    -- 3. NEET_OS: シャットダウンフック (Wayland が閉じる前に graphical-session を停止)
    hl.on("hyprland.shutdown", function()
      local live_dir = os.getenv("S6_LIVE_DIR")
      if live_dir then
        os.execute("${pkgs.s6-rc}/bin/s6-rc -l " .. live_dir .. " -d change graphical-session")
      end
    end)
  '';
in {
  options = {
    # ─── システム全体の設定（WMの有効化・インフラ） ───
    programs.hyprland = {
      enable = mkEnableOption "Hyprland Wayland compositor";

      package = mkOption {
        type = types.package;
        default = hyprlandPackage;
        description = "使用する Hyprland パッケージ";
      };
    };

    # ─── ユーザーごとの設定（サブモジュール拡張） ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.hyprland;
        hasConfigFile = userCfg.configFile != null;
        hasExtraConfig = userCfg.extraConfig != "";
        hasConfig = hasConfigFile || hasExtraConfig;

        targetConfig =
          if hasConfigFile
          then userCfg.configFile
          else pkgs.writeText "hyprland-${name}.lua" userCfg.extraConfig;
      in {
        options.programs.hyprland = {
          configFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "ユーザー固有の hyprland.lua ファイルパス";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "インラインで書くユーザー固有の Lua 設定";
          };
        };

        config = mkIf hasConfig {
          assertions = [
            {
              assertion = !(hasConfigFile && hasExtraConfig);
              message = "neet.users.${name}.programs.hyprland: `configFile` と `extraConfig` を両方指定することはできません。";
            }
          ];

          # ラッパーが探索するパス (/etc/users/<name>/files/hypr/hyprland.lua) に配置
          files."hypr/hyprland.lua".source = targetConfig;
        };
      }));
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
      # どのユーザーがログインしても共通ラッパーを呼ぶ（ラッパー側で実行時ユーザーの設定を dofile する）
      command = "${cfg.package}/bin/start-hyprland --path ${getExe cfg.package} -- --config ${wrapperConfig}";
      displayName = "Hyprland";
      comment = "Dynamic tiling Wayland compositor";
      desktopNames = ["Hyprland"];
    };

    environment.systemPackages = [cfg.package pkgs.qt6.qtwayland];
  };
}
