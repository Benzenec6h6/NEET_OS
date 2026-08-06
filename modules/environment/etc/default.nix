{
  pkgs,
  lib,
  config,
  ...
}: let
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
      # 権限を指定できるようにする
      mode = lib.mkOption {
        type = lib.types.str;
        default = "0444";
      };
    };
    config.source = lib.mkIf (config.text != null) (pkgs.writeText "etc-${name}" config.text);
  };

  etcDirectory = pkgs.runCommand "etc-static-dir" {} ''
    mkdir -p $out
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (name: value: ''
        mkdir -p "$out/$(dirname "${value.target}")"
        ln -s "${value.source}" "$out/${value.target}"
        # 権限情報を隠しファイルとして記録（etc-syncerで使用可能にする）
        echo "${value.mode}" > "$out/${value.target}.mode"
      '')
      config.environment.etc)}
  '';
in {
  options.environment.etc = lib.mkOption {
    type = lib.types.attrsOf (lib.types.submodule etcOpts);
    default = {};
  };
  options.system.etcDir = lib.mkOption {
    internal = true;
    type = lib.types.path;
  };
  config.system.etcDir = etcDirectory;
}
