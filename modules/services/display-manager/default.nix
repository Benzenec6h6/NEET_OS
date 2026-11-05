{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.displayManager;

  sessionBins = pkgs.linkFarm "neet-sessions" (
    mapAttrs (name: s:
      pkgs.writeShellScript "neet-session-${name}" ''
        export XDG_CURRENT_DESKTOP=${escapeShellArg (concatStringsSep ":" s.desktopNames)}
        exec ${s.command}
      '')
    cfg.sessions
  );

  # lemurs は Exec を直接実行するのでランナーを明示する。
  # greetd(tuigreet) は --session-wrapper が前置されるのでセッション名だけ渡す。
  sessionExec = name:
    if cfg.provider == "lemurs"
    then "${getExe cfg.sessionWrapper} ${name}"
    else name;

  sessionFiles = pkgs.symlinkJoin {
    name = "neet-wayland-sessions";
    paths = mapAttrsToList (name: s:
      pkgs.writeTextDir "share/wayland-sessions/${name}.desktop" ''
        [Desktop Entry]
        Name=${s.displayName}
        Comment=${s.comment}
        Exec=${sessionExec name}
        Type=Application
        DesktopNames=${concatStringsSep ";" s.desktopNames}
      '')
    cfg.sessions;
  };

  userSessionRunner = pkgs.writeShellApplication {
    name = "neet-user-session";
    runtimeInputs = with pkgs; [s6 s6-rc coreutils util-linux];
    text = ''
      export SESSIONS_DIR=${sessionBins}
      export DEFAULT_SESSION=${escapeShellArg cfg.defaultSession}
      ${builtins.readFile ./user-session.sh}
    '';
  };

  # WM起動後(exec-once等)に呼ばれ、環境をenvdirへ書き出して graphical-session を起動する。
  # WM固有の変数名は引数で受け取る (例: HYPRLAND_INSTANCE_SIGNATURE)
  sessionReady = pkgs.writeShellApplication {
    name = "neet-session-ready";
    runtimeInputs = with pkgs; [s6-rc coreutils];
    text = ''
      envdir="''${XDG_RUNTIME_DIR:?}/env"
      mkdir -p "$envdir"
      for v in WAYLAND_DISPLAY XDG_CURRENT_DESKTOP XDG_SESSION_TYPE \
               DBUS_SESSION_BUS_ADDRESS "$@"; do
        if [ -n "''${!v-}" ]; then
          printf %s "''${!v}" > "$envdir/$v"
        fi
      done
      exec s6-rc -l "''${S6_LIVE_DIR:?}" -u change graphical-session
    '';
  };

  pamText = ''
    auth      required    ${pkgs.pam}/lib/security/pam_unix.so nullok
    account   required    ${pkgs.pam}/lib/security/pam_unix.so
    password  required    ${pkgs.pam}/lib/security/pam_unix.so sha512 shadow nullok
    session   required    ${pkgs.pam}/lib/security/pam_env.so
    session   optional    ${pkgs.pam}/lib/security/pam_loginuid.so
    session   required    ${pkgs.pam}/lib/security/pam_unix.so
    ${optionalString config.services.sessiond.enable
      "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"}
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
      type = types.attrsOf (types.submodule ({name, ...}: {
        options = {
          command = mkOption {
            type = types.str;
            description = "セッションの起動コマンドライン";
          };
          displayName = mkOption {
            type = types.str;
            default = name;
            description = "DMのセッション選択に表示される名前";
          };
          comment = mkOption {
            type = types.str;
            default = "";
            description = ".desktop の Comment";
          };
          desktopNames = mkOption {
            type = types.listOf types.str;
            default = [name];
            description = "XDG_CURRENT_DESKTOP / DesktopNames に使う名前";
          };
        };
      }));
      default = {};
      description = "システムに登録された利用可能なグラフィカルセッション一覧 (Waylandのみ。X11が必要ならXWaylandを使う)";
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
      description = "ユーザーログイン時に実行されるセッションランナー (meta.mainProgram が必要。`getExe` で参照する)";
    };

    sessionReady = mkOption {
      type = types.package;
      default = sessionReady;
      readOnly = true;
      description = "WM起動後に呼び出し、graphical-session を起動するヘルパー。WM固有の環境変数名を引数に取る";
    };
  };

  config = mkIf cfg.enable {
    assertions = [
      {
        assertion = cfg.sessions ? ${cfg.defaultSession};
        message = "displayManager: defaultSession '${cfg.defaultSession}' は有効化されたどのセッションとも一致しません。";
      }
    ];

    # パッケージ同梱の .desktop より優先させる
    environment.systemPackages = [(hiPrio sessionFiles)];

    neet.security.pam.services = {
      greetd.text = mkIf (cfg.provider == "greetd") pamText;
      lemurs.text = mkIf (cfg.provider == "lemurs") pamText;
    };

    services.dbus.enable = true;
  };
}
