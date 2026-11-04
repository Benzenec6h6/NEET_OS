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

    # ★ 1. 最重要: s6, s6-rc, coreutils などの PATH を確実に通す
    export PATH="${lib.makeBinPath [
      pkgs.s6
      pkgs.s6-rc
      pkgs.coreutils
      pkgs.util-linux
    ]}:/run/current-system/bin:/run/wrappers/bin:$PATH"

    TARGET_WM="''${1:-${cfg.defaultSession}}"

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
      # ★ 2. 前回の古い残骸（壊れたリンクなど）を確実にクリーンアップ
      rm -rf "$LIVE_DIR" "$SERVICE_DIR"
      mkdir -p "$SERVICE_DIR"

      if [ -d "$DEFINITIONS" ]; then
        rm -rf "$XDG_RUNTIME_DIR/service-definitions"
        ln -sfn "$DEFINITIONS" "$XDG_RUNTIME_DIR/service-definitions"
      fi

      # 1. ユーザー用 s6-svscan をバックグラウンド起動
      s6-svscan "$SERVICE_DIR" &
      SVSCAN_PID=$!

      # コントロールソケットの準備ができるのを待つ
      until [ -p "$SERVICE_DIR/.s6-svscan/control" ] || [ -S "$SERVICE_DIR/.s6-svscan/control" ]; do
        sleep 0.05
      done

      # ★ 3. s6-svscan が監視ループに入るのを少し確実に待つ
      s6-svscanctl -a "$SERVICE_DIR" 2>/dev/null || true

      # 2. s6-rc の初期化
      s6-rc-init -c "$COMPILED_DB" -l "$LIVE_DIR" "$SERVICE_DIR"

      # 3. 基本サービス (D-Bus 等) を起動
      s6-rc -l "$LIVE_DIR" -u change top

      # 4. DM で選ばれた WM を起動！
      if [ -n "$TARGET_WM" ]; then
        # ※ TARGET_WM に .desktop のパスが渡ってきた場合の保険 (basename で "hyprland" にする)
        WM_NAME="$(basename "$TARGET_WM" .desktop)"
        s6-rc -l "$LIVE_DIR" -u change "$WM_NAME"
      fi

      # 5. セッション維持 (svscan の終了を見守る)
      wait $SVSCAN_PID 2>/dev/null || true

      # 6. ログアウト処理
      if [ -d "$LIVE_DIR" ]; then
        s6-rc -l "$LIVE_DIR" -da change || true
      fi
      s6-svscanctl -t "$SERVICE_DIR" || true

    else
      if [ -n "$1" ]; then
        exec "$@"
      else
        exec /bin/sh
      fi
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
