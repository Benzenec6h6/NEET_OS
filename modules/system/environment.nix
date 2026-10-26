{
  pkgs,
  lib,
  config,
  ...
}: let
  neetRebuild = pkgs.writeShellScriptBin "neet-rebuild" (builtins.readFile ./rebuild.sh);
  neetGC = pkgs.writeShellScriptBin "neet-gc" (builtins.readFile ./gc.sh);
  neetInstall = pkgs.writeShellScriptBin "neet-install" (builtins.readFile ./install.sh);
  inherit (lib) mkOption types;

  dirOpts = types.submodule {
    options = {
      path = mkOption {
        type = types.str;
        description = "作成するディレクトリの絶対パス";
      };
      mode = mkOption {
        type = types.str;
        default = "0755";
        description = "パーミッション（8進数文字列 例: '0755'）";
      };
      user = mkOption {
        type = types.str;
        default = "root";
        description = "所有ユーザー名";
      };
      group = mkOption {
        type = types.str;
        default = "root";
        description = "所有グループ名";
      };
    };
  };
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

    system.stateDirectories = mkOption {
      type = types.listOf dirOpts;
      default = [];
      merge = lib.concatLists;
      description = "neet-activate によって起動時/切り替え時に作成・権限設定されるディレクトリ群";
    };
  };

  config = {
    # 必須の基幹ツール群を標準で含める
    environment.systemPackages = with pkgs; [
      neetRebuild
      neetGC
      neetInstall
      config.environment.execline

      # 基本の UNIX ツール群
      util-linux
      findutils
      diffutils
      iputils
      gnugrep
      gawk
      procps
      which
      less
    ];

    environment.variables = {
      PATH = [
        "/run/wrappers/bin"
        "/run/current-system/bin"
        "/bin"
        "/sbin"
      ];
      TERM = "linux";
      NIX_REMOTE = "daemon";
      SSL_CERT_FILE = "/etc/ssl/certs/ca-certificates.crt";
      CURL_CA_BUNDLE = "/etc/ssl/certs/ca-certificates.crt";
    };

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

    # 1. 散らばっていた FHS 基本骨格をここに定義
    system.stateDirectories = [
      {
        path = "/mnt";
        mode = "0755";
      }
      {
        path = "/media";
        mode = "0755";
      }
      {
        path = "/opt";
        mode = "0755";
      }
      {
        path = "/srv";
        mode = "0755";
      }
      {
        path = "/root";
        mode = "0700";
      }
      {
        path = "/tmp";
        mode = "1777";
      }
      {
        path = "/var/log";
        mode = "0755";
      }
      {
        path = "/var/lib";
        mode = "0755";
      }
      {
        path = "/var/db";
        mode = "0755";
      }
      {
        path = "/var/empty";
        mode = "0755";
      }
      {
        path = "/run/lock";
        mode = "1777";
      }
      {
        path = "/run/sessiond";
        mode = "0755";
      }
    ];

    # 2. JSON として /etc 配下にエクスポート
    # etc.nix や etc_syncer を通じて /etc/state-directories.json に配置される
    environment.etc."state-directories.json".text =
      builtins.toJSON config.system.stateDirectories;

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
