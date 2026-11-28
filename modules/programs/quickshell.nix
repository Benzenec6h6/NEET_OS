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

  anyUserEnabled = cfg.enable || any (u: u.programs.quickshell.enable) (attrValues config.neet.users);
in {
  options = {
    programs.quickshell = {
      enable = mkEnableOption "Quickshell desktop shell under graphical-session";

      package = mkOption {
        type = types.package;
        default = pkgs.quickshell;
        description = "使用する Quickshell パッケージ";
      };

      configDir = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "システム共通の Quickshell 設定ディレクトリ。null の場合は ~/.config/quickshell を参照";
      };
    };

    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.quickshell;

        startCmd =
          if userCfg.configDir != null
          then "${wrappedQuickshell}/bin/quickshell -p ${userCfg.configDir}"
          else "${wrappedQuickshell}/bin/quickshell";
      in {
        options.programs.quickshell = {
          enable = mkOption {
            type = types.bool;
            default = cfg.enable && config.isSessionUser;
            description = "ユーザー '${name}' で Quickshell を起動するかどうか";
          };

          configDir = mkOption {
            type = types.nullOr types.path;
            default = cfg.configDir;
            description = "ユーザー固有の Quickshell 設定ディレクトリ。null の場合は ~/.config/quickshell を参照";
          };
        };

        config = mkIf userCfg.enable {
          # ★ s6.services に定義
          s6.services.quickshell = {
            type = "longrun";
            autoStart = false;
            partOf = ["graphical-session"];
            log.enable = true;
            run = ''
              #!/bin/sh
              exec ${startCmd}
            '';
          };
        };
      }));
    };
  };

  config = mkIf anyUserEnabled {
    environment.systemPackages = [wrappedQuickshell];
  };
}
