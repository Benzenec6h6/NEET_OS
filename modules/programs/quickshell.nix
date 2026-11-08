{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.quickshell;

  qtDeps = with pkgs.qt6; [
    qtsvg
    qtimageformats
    qtmultimedia
    qt5compat
    qtdeclarative
    qtwayland
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
    environment.systemPackages = [wrappedQuickshell];

    # ★ sessionUsers を直接 mapAttrs で回す
    system.s6-rc.users =
      mapAttrs (_username: user: {
        services.quickshell = {
          type = "longrun";
          autoStart = false;
          partOf = ["graphical-session"];
          envdirs = ["/run/user/${toString user.uid}/env"];

          run = ''
            #!/bin/execlineb -P
            fdmove -c 2 1
            ${startCmd}
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
