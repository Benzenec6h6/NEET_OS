{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.displayManager;

  userSessionRunner = pkgs.writeShellScript "neet-user-session" ''
    set -e

    USER_NAME="$(id -un)"
    USER_UID="$(id -u)"
    export XDG_RUNTIME_DIR="/run/user/$USER_UID"
    export HOME="''${HOME:-/home/$USER_NAME}"
    export XDG_SESSION_TYPE=wayland

    if [ -S /run/seatd/seatd.sock ]; then
      export SEATD_SOCK=/run/seatd/seatd.sock
    fi

    SERVICE_DIR="$XDG_RUNTIME_DIR/service"
    LIVE_DIR="$XDG_RUNTIME_DIR/s6-rc"
    COMPILED_DB="/etc/s6-rc/users/$USER_NAME/compiled"
    DEFINITIONS="/etc/s6-rc/users/$USER_NAME/definitions"

    if [ -d "$COMPILED_DB" ]; then
      mkdir -p "$SERVICE_DIR"

      # restartOnUpdate = false 用の実体スクリプト群をリンク
      if [ -d "$DEFINITIONS" ]; then
        rm -rf "$XDG_RUNTIME_DIR/service-definitions"
        ln -sfn "$DEFINITIONS" "$XDG_RUNTIME_DIR/service-definitions"
      fi

      # 1. ユーザー用 s6-svscan をバックグラウンド起動
      ${pkgs.s6}/bin/s6-svscan "$SERVICE_DIR" &
      SVSCAN_PID=$!

      until [ -p "$SERVICE_DIR/.s6-svscan/control" ] || [ -S "$SERVICE_DIR/.s6-svscan/control" ]; do
        sleep 0.05
      done

      # 2. s6-rc を初期化してトップサービス群を一括起動！
      ${pkgs.s6-rc}/bin/s6-rc-init -c "$COMPILED_DB" -l "$LIVE_DIR" "$SERVICE_DIR"
      ${pkgs.s6-rc}/bin/s6-rc -l "$LIVE_DIR" -u change top

      # 3. セッション維持 (svscan の終了を見守る)
      wait $SVSCAN_PID 2>/dev/null || true

      # 4. ログアウト処理
      if [ -d "$LIVE_DIR" ]; then
        ${pkgs.s6-rc}/bin/s6-rc -l "$LIVE_DIR" -da change || true
      fi
      ${pkgs.s6}/bin/s6-svscanctl -t "$SERVICE_DIR" || true

    else
      if [ -n "$1" ]; then
        exec "$@"
      else
        exec /bin/sh
      fi
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
      default = 1;
      description = "DMが使用する仮想端末 (VT/TTY) 番号";
    };

    sessionWrapper = mkOption {
      type = types.package;
      default = userSessionRunner;
      description = "ユーザーログイン時に実行されるセッションランナー";
    };
  };

  config = mkIf cfg.enable {
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
