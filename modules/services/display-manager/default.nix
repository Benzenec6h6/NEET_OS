{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.displayManager;

  # 純粋な Wayland 用セッションラッパー
  sessionWrapper = pkgs.writeShellScript "neet-wayland-session" ''
    set -e

    # 1. XDG_RUNTIME_DIR の担保
    if [ -z "$XDG_RUNTIME_DIR" ]; then
      export XDG_RUNTIME_DIR="/run/user/$(id -u)"
      if [ ! -d "$XDG_RUNTIME_DIR" ]; then
        mkdir -p "$XDG_RUNTIME_DIR"
        chmod 0700 "$XDG_RUNTIME_DIR"
      fi
    fi

    # 2. Wayland 必須環境変数
    export XDG_SESSION_TYPE=wayland
    export XDG_CURRENT_DESKTOP="''${XDG_CURRENT_DESKTOP:-wlroots}"
    export MOZ_ENABLE_WAYLAND=1
    export QT_QPA_PLATFORM="wayland;xcb"
    export _JAVA_AWT_WM_NONREPARENTING=1

    # 3. seatd ソケット
    if [ -S /run/seatd/seatd.sock ]; then
      export SEATD_SOCK=/run/seatd/seatd.sock
    fi

    # 4. D-Bus セッションバスを立ち上げてコンポジタを exec
    if command -v ${pkgs.dbus}/bin/dbus-run-session >/dev/null 2>&1; then
      exec ${pkgs.dbus}/bin/dbus-run-session -- "$@"
    else
      exec "$@"
    fi
  '';
in {
  imports = [
    ./greetd.nix
    ./ly.nix
  ];

  options.services.displayManager = {
    enable = mkEnableOption "Display Manager";

    provider = mkOption {
      type = types.enum ["greetd" "ly"];
      default = "ly";
      description = "使用するディスプレイマネージャ実装";
    };

    tty = mkOption {
      type = types.int;
      default = 1; # tty1 をメインに設定
      description = "DMが使用する仮想端末 (VT/TTY) 番号";
    };

    defaultSession = mkOption {
      type = types.str;
      default = "";
      example = "hyprland";
      description = "デフォルトで起動するコンポジタ/セッションコマンド";
    };

    sessionWrapper = mkOption {
      type = types.package;
      default = sessionWrapper;
      description = "Waylandセッション起動時に環境を整備するラッパースクリプト";
    };
  };

  config = mkIf cfg.enable {
    # PAM 設定に pam_sessiond.so を組み込み（デバイス権限委譲）
    neet.security.pam.services = {
      greetd.text = mkIf (cfg.provider == "greetd") ''
        auth      required    ${pkgs.pam}/lib/security/pam_unix.so nullok
        account   required    ${pkgs.pam}/lib/security/pam_unix.so
        password  required    ${pkgs.pam}/lib/security/pam_unix.so sha512 shadow nullok
        session   required    ${pkgs.pam}/lib/security/pam_unix.so
        ${optionalString config.services.sessiond.enable
          "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"}
      '';

      ly.text = mkIf (cfg.provider == "ly") ''
        auth      required    ${pkgs.pam}/lib/security/pam_unix.so nullok
        account   required    ${pkgs.pam}/lib/security/pam_unix.so
        password  required    ${pkgs.pam}/lib/security/pam_unix.so sha512 shadow nullok
        session   required    ${pkgs.pam}/lib/security/pam_unix.so
        ${optionalString config.services.sessiond.enable
          "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"}
      '';
    };

    services.dbus.enable = true;
  };
}
