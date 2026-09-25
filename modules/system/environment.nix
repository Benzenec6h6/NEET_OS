{
  pkgs,
  lib,
  config,
  ...
}: let
  neetRebuild = pkgs.writeShellScriptBin "neet-rebuild" (builtins.readFile ./rebuild.sh);
in {
  options = {
    environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
    };

    environment.pathsToLink = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [
        "/bin"
        "/sbin"
        "/share/vulkan"
      ];
      description = "Directories to be symlinked in system-path";
    };

    environment.execline = lib.mkOption {
      type = lib.types.package;
      default = pkgs.execline;
      description = ''
        execline package. /bin/execlineb from this package is relied upon,
        by literal absolute path, as the interpreter for PID 1's init script.
      '';
    };

    system.path = lib.mkOption {
      internal = true;
      type = lib.types.path;
    };
  };

  config = {
    # 必須の基幹ツール群を標準で含める
    environment.systemPackages = with pkgs; [
      neetRebuild
      config.environment.execline

      # 基本の UNIX ツール群
      util-linux
      findutils
      gnugrep
      gawk
      procps
      which
      less
    ];

    system.path = pkgs.buildEnv {
      name = "system-path";
      paths =
        config.environment.systemPackages
        ++ lib.optionals (config.hardware.graphics.enable or false) [
          (pkgs.runCommand "graphics-drivers-syspath" {} ''
            mkdir -p $out
            ln -s ${config.system.build.graphicsDrivers} $out/graphics-drivers
            ${lib.optionalString (config.hardware.graphics.enable32Bit or false) ''
              ln -s ${config.system.build.graphicsDrivers32} $out/graphics-drivers-32bit
            ''}
          '')
        ];
      pathsToLink = config.environment.pathsToLink;
      ignoreCollisions = true;

      postBuild = ''
        # タブ補完を汚すラッパーバイナリを消去
        find $out/bin -maxdepth 1 -name ".*-wrapped" -type l -delete

        # GSettings / GLib スキーマのコンパイル
        if [ -x $out/bin/glib-compile-schemas -a -w $out/share/glib-2.0/schemas ]; then
          $out/bin/glib-compile-schemas $out/share/glib-2.0/schemas
        fi
      '';
    };

    # 最重要：名前解決とユーザー解決の基盤
    environment.etc."nsswitch.conf".text = ''
      passwd:         files
      group:          files
      shadow:         files

      hosts:          files dns
      networks:       files
    '';

    environment.etc."os-release".text = ''
      NAME="NEET OS"
      ID=neet-os
      PRETTY_NAME="NEET OS v0.1"
    '';
  };
}
