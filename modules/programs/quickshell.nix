{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.quickshell;

  # Quickshell が必要とする QML モジュール群を安全に束ねる
  qtDeps = with pkgs.qt6; [
    qtsvg # SVG アイコン描画
    qtimageformats # WebP などの画像フォーマット
    qtmultimedia # 音声・動画再生
    qt5compat # 旧エフェクト互換
    qtdeclarative # QML 基本ライブラリ
    qtwayland # Wayland サポート
  ];

  wrappedQuickshell = pkgs.symlinkJoin {
    name = "quickshell-wrapped";
    paths = [cfg.package];
    buildInputs = [pkgs.makeWrapper];
    postBuild = let
      qmlPath = concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/qml") qtDeps;
      pluginPath = concatMapStringsSep ":" (pkg: "${pkg}/lib/qt-6/plugins") qtDeps;
    in ''
      wrapProgram $out/bin/quickshell \
        --prefix QML_IMPORT_PATH : "${qmlPath}" \
        --prefix QML2_IMPORT_PATH : "${qmlPath}" \
        --prefix QT_PLUGIN_PATH : "${pluginPath}" \
        --set QT_QPA_PLATFORM "wayland" \
        --set QT_WAYLAND_DISABLE_WINDOWDECORATION "1"
    '';
  };

  # 起動コマンドの決定 (パス指定があれば -p を付与)
  startCmd =
    if cfg.configDir != null
    then "${wrappedQuickshell}/bin/quickshell -p ${cfg.configDir}"
    else "${wrappedQuickshell}/bin/quickshell";
in {
  options.programs.quickshell = {
    enable = mkEnableOption "Quickshell desktop shell under graphical-session";

    package = mkOption {
      type = types.package;
      default = pkgs.quickshell;
      description = "Quickshell package to use";
    };

    configDir = mkOption {
      type = types.nullOr types.path;
      default = null;
      description = "Quickshell 設定ディレクトリ。null の場合は ~/.config/quickshell を参照します";
    };
  };

  config = mkIf cfg.enable {
    # ユーザーが直接端末からも叩けるようにパッケージ配置
    environment.systemPackages = [wrappedQuickshell];

    # graphical-session にぶら下げるサービス定義 (例: 単一ユーザー構成の場合)
    # ※ NEET_OS の s6-rc ユーザーサービスの仕組みに合わせて接続してください
    system.s6-rc.users = genAttrs users (username: let
      uid = toString config.neet.users.${username}.uid;
    in {
      services.quickshell = {
        type = "longrun";
        autoStart = false; # top には含めない (ログイン直後は起動しない)
        partOf = ["graphical-session"]; # ★ WM (Sway/Hyprland) 起動時に連動！
        envdirs = ["/run/user/${uid}/env"]; # ★ display-manager の Wayland 環境変数を注入

        run = ''
          #!/bin/execlineb -P
          fdmove -c 2 1
          ${startCmd}
        '';
      };
    });
  };
}
