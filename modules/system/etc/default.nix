{
  pkgs,
  lib,
  config,
  ...
}: let
  # 1. 内部で Rust ツールをビルド
  etcSyncer = pkgs.pkgsStatic.rustPlatform.buildRustPackage {
    pname = "etc-syncer";
    version = "0.1.0";
    src = ./etc-syncer;
    cargoLock.lockFile = ./etc-syncer/Cargo.lock;
  };

  # 2. etc フォルダ内の各ファイルの設定
  etcOpts = {
    name,
    config,
    ...
  }: {
    options = {
      text = lib.mkOption {
        type = lib.types.nullOr lib.types.lines;
        default = null;
      };
      source = lib.mkOption {type = lib.types.path;};
      target = lib.mkOption {
        type = lib.types.str;
        default = name;
      };
      mode = lib.mkOption {
        type = lib.types.str;
        default = "symlink";
      };
      uid = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      gid = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
    };
    config.source = lib.mkIf (config.text != null) (pkgs.writeText "etc-${name}" config.text);
  };

  # 3. ストア内の etc ディレクトリ構造の生成
  etcDirectory = pkgs.runCommand "etc-static-dir" {} ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
        mkdir -p "$out/$(dirname "${value.target}")"
        ln -s "${value.source}" "$out/${value.target}"
        ${lib.optionalString (value.mode != "symlink") ''
          echo "${value.mode}" > "$out/${value.target}.mode"
          echo "+${toString value.uid}" > "$out/${value.target}.uid"
          echo "+${toString value.gid}" > "$out/${value.target}.gid"
        ''}
      '')
      config.environment.etc)}
  '';
in {
  options = {
    environment.etc = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule etcOpts);
      default = {};
    };

    system.etc.package = lib.mkOption {
      internal = true;
      type = lib.types.path;
    };

    system.etc.bin = lib.mkOption {
      internal = true;
      type = lib.types.package;
    };
  };

  config = {
    system.etc.package = etcDirectory;
    system.etc.bin = etcSyncer;

    # ツール自体をシステムパッケージに追加
    environment.systemPackages = [etcSyncer];

    system.activationScripts.etc = ''
      ${config.system.etc.bin}/bin/etc-syncer ${config.system.etc.package}
    '';
  };
}
