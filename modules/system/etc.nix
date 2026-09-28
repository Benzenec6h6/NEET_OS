{
  pkgs,
  lib,
  config,
  ...
}: let
  # etc フォルダ内の各ファイルの設定
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

  # ストア内の etc ディレクトリ構造の生成
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
    # inieet.nix が定義した systemInit を参照
    system.etc.bin = config.system.build.systemInit;
  };
}
