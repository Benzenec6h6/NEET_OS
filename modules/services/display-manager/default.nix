{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.displayManager;

  # デフォルトセッションのコマンドを安全に解決
  defaultSessionCmd =
    if cfg.sessions ? ${cfg.defaultSession}
    then cfg.sessions.${cfg.defaultSession}.command
    else throw "displayManager: defaultSession '${cfg.defaultSession}' は有効化されたどのセッションとも一致しません。";

  userSessionRunner = pkgs.writeShellScript "neet-user-session" ''
    exec > /tmp/neet-user-session.log 2>&1
    set -ex

    export PATH="${lib.makeBinPath [
      pkgs.s6
      pkgs.s6-rc
      pkgs.coreutils
      pkgs.util-linux
    ]}:/run/current-system/bin:/run/wrappers/bin:$PATH"

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
    COMPILED_DB="/var/lib/s6-rc/users/$USER_NAME/compiled"

    if [ -d "$COMPILED_DB" ]; then
      rm -rf "$LIVE_DIR" "$SERVICE_DIR"
      mkdir -p "$SERVICE_DIR"

      s6-svscan "$SERVICE_DIR" &
      SVSCAN_PID=$!

      until [ -p "$SERVICE_DIR/.s6-svscan/control" ] || [ -S "$SERVICE_DIR/.s6-svscan/control" ]; do
        sleep 0.05
      done

      s6-rc-init -c "$COMPILED_DB" -l "$LIVE_DIR" "$SERVICE_DIR"
      s6-rc -l "$LIVE_DIR" -u change top

      # ★ ここを追加: Wayland ソケットを待って graphical-session を起こすウォッチャー
      (
        for i in $(seq 1 50); do
          SOCKET=$(find "$XDG_RUNTIME_DIR" -maxdepth 1 -name "wayland-[0-9]*" -type s 2>/dev/null | head -n 1)
          if [ -n "$SOCKET" ]; then
            # 1. 環境変数を envdir に書き出し
            mkdir -p "$XDG_RUNTIME_DIR/env"
            echo -n "$(basename "$SOCKET")" > "$XDG_RUNTIME_DIR/env/WAYLAND_DISPLAY"
            echo -n "$XDG_RUNTIME_DIR"       > "$XDG_RUNTIME_DIR/env/XDG_RUNTIME_DIR"
            echo -n "wayland"                > "$XDG_RUNTIME_DIR/env/XDG_SESSION_TYPE"
            if [ -S "$XDG_RUNTIME_DIR/bus" ]; then
              echo -n "unix:path=$XDG_RUNTIME_DIR/bus" > "$XDG_RUNTIME_DIR/env/DBUS_SESSION_BUS_ADDRESS"
            fi

            # 2. GUI セッションサービス群を一斉起動！
            s6-rc -l "$LIVE_DIR" -u change graphical-session 2>/dev/null || true
            break
          fi
          sleep 0.1
        done
      ) &
      WATCHER_PID=$!

      # WM の実行（フォアグラウンド）
      SESSION_CHOICE="''${1:-${cfg.defaultSession}}"
      WM_KEY="$(basename "$SESSION_CHOICE" .desktop)"

      case "$WM_KEY" in
        ${concatStringsSep "\n" (mapAttrsToList (name: session: ''
        "${name}")
          ${session.command} || true
          ;;
      '')
      cfg.sessions)}
        *)
          ${defaultSessionCmd} || true
          ;;
      esac

      # ★ WM が終了したら、PropagatesStopTo のごとく道連れ停止！
      kill $WATCHER_PID 2>/dev/null || true
      s6-rc -l "$LIVE_DIR" -d change graphical-session 2>/dev/null || true

      if [ -d "$LIVE_DIR" ]; then
        s6-rc -l "$LIVE_DIR" -da change || true
      fi
      s6-svscanctl -t "$SERVICE_DIR" || true
      wait $SVSCAN_PID 2>/dev/null || true
    fi
  '';

  defaultVtTty =
    if (config.boot ? vt && config.boot.vt.consoles != [])
    then builtins.head config.boot.vt.consoles
    else 1;
in {
  imports = [
    ./greetd.nix
    ./lemurs.nix
  ];

  options.services.displayManager = {
    enable = mkEnableOption "Display Manager";

    sessions = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          command = mkOption {
            type = types.str;
            description = "セッションの起動コマンドライン";
          };
        };
      });
      default = {};
      description = "システムに登録された利用可能なグラフィカルセッション一覧";
    };

    provider = mkOption {
      type = types.enum ["greetd" "lemurs"];
      default = "lemurs";
      description = "使用するディスプレイマネージャ実装";
    };

    defaultSession = mkOption {
      type = types.str;
      default = "hyprland";
      example = "hyprland";
      description = "デフォルトで選択・起動されるセッション名";
    };

    tty = mkOption {
      type = types.int;
      default = defaultVtTty;
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
        session   required    ${pkgs.pam}/lib/security/pam_env.so
        session   optional    ${pkgs.pam}/lib/security/pam_loginuid.so
        session   required    ${pkgs.pam}/lib/security/pam_unix.so
        ${optionalString config.services.sessiond.enable
          "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"}
      '';

      lemurs.text = mkIf (cfg.provider == "lemurs") ''
        auth      required    ${pkgs.pam}/lib/security/pam_unix.so nullok
        account   required    ${pkgs.pam}/lib/security/pam_unix.so
        password  required    ${pkgs.pam}/lib/security/pam_unix.so sha512 shadow nullok
        session   required    ${pkgs.pam}/lib/security/pam_env.so
        session   optional    ${pkgs.pam}/lib/security/pam_loginuid.so
        session   required    ${pkgs.pam}/lib/security/pam_unix.so
        ${optionalString config.services.sessiond.enable
          "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"}
      '';
    };

    services.dbus.enable = true;
  };
}
