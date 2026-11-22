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

  # 実行時ユーザーの環境に応じてラッパー設定を生成し、Sway を起動するセッションスクリプト
  swaySession = pkgs.writeShellScript "sway-session" ''
    set -eu

    status=0
    cleanup() {
      trap - EXIT INT TERM
      if [ -n "''${S6_LIVE_DIR:-}" ]; then
        ${pkgs.s6-rc}/bin/s6-rc -l "$S6_LIVE_DIR" -d change graphical-session || true
      fi
      exit "$status"
    }
    trap cleanup EXIT INT TERM

    user="$(id -un)"
    runtime_dir="''${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
    wrapper_conf="$runtime_dir/sway-wrapper.conf"

    # ユーザー設定ファイルの探索
    # 1. Nix で宣言された設定 (/etc/users/<USER>/files/sway/config)
    # 2. ユーザー手動の dotfile (~/.config/sway/config)
    # 3. システムデフォルト (/etc/sway/config)
    user_nix_conf="/etc/users/$user/files/sway/config"
    user_dot_conf="$HOME/.config/sway/config"
    sys_default_conf="/etc/sway/config"

    target_include=""
    if [ -f "$user_nix_conf" ]; then
      target_include="include $user_nix_conf"
    elif [ -f "$user_dot_conf" ]; then
      target_include="include $user_dot_conf"
    elif [ -f "$sys_default_conf" ]; then
      target_include="include $sys_default_conf"
    fi

    # 動的ラッパー設定を出力
    cat <<EOF > "$wrapper_conf"
    $target_include
    # NEET_OS: 起動完了イベント通知
    exec ${getExe config.services.displayManager.sessionReady} SWAYSOCK
    EOF

    ${getExe cfg.package} --config "$wrapper_conf"
    status=$?
  '';
in {
  options = {
    # ─── システム全体の設定（WMの有効化・インフラ） ───
    programs.sway = {
      enable = mkEnableOption "Sway Wayland compositor";

      package = mkOption {
        type = types.package;
        default = swayPackage;
        description = "使用する Sway パッケージ";
      };
    };

    # ─── ユーザーごとの設定 ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.sway;
        hasConfigFile = userCfg.configFile != null;
        hasExtraConfig = userCfg.extraConfig != "";
        hasConfig = hasConfigFile || hasExtraConfig;

        targetConfig =
          if hasConfigFile
          then userCfg.configFile
          else pkgs.writeText "sway-${name}-config" userCfg.extraConfig;
      in {
        options.programs.sway = {
          configFile = mkOption {
            type = types.nullOr types.path;
            default = null;
            description = "ユーザー固有の Sway 設定ファイルパス";
          };

          extraConfig = mkOption {
            type = types.lines;
            default = "";
            description = "インラインで書くユーザー固有の Sway 設定";
          };
        };

        config = mkIf hasConfig {
          assertions = [
            {
              assertion = !(hasConfigFile && hasExtraConfig);
              message = "neet.users.${name}.programs.sway: `configFile` と `extraConfig` を両方指定することはできません。";
            }
          ];

          # 探索パス (/etc/users/<name>/files/sway/config) に配置
          files."sway/config".source = targetConfig;
        };
      }));
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
      command = "${swaySession}";
      displayName = "Sway";
      comment = "An i3-compatible Wayland compositor";
      desktopNames = ["sway" "wlroots"];
    };

    environment.systemPackages = [cfg.package];
  };
}
