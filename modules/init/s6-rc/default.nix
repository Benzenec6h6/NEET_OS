{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.system.s6-rc;

  serviceOpts = {name, ...}: {
    options = {
      type = mkOption {type = types.enum ["longrun" "oneshot"];};
      run = mkOption {
        type = types.lines;
        default = "";
      };
      up = mkOption {
        type = types.lines;
        default = "";
      };
      down = mkOption {
        type = types.lines;
        default = "";
      };
      dependencies = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      notification-fd = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      format = mkOption {
        type = types.enum ["execline" "sh"];
        default = "execline";
        description = "oneshot スクリプトの記述言語 (execline または sh)";
      };
      logRun = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "s6-log等によるロガー用スクリプト (log/run)。longrunサービスのみ有効。";
      };
    };
  };

  # ソースディレクトリの組み立て
  s6SourceDir = import ./build-source.nix {
    inherit lib pkgs;
    inherit (cfg) services;
  };
in {
  options.system.s6-rc = {
    services = mkOption {
      type = types.attrsOf (types.submodule serviceOpts);
      default = {};
      description = "s6-rcサービス定義の集合";
    };
  };

  config = mkIf (cfg.services != {}) {
    # コンパイル済みDBの構築
    system.build.s6-rc-db =
      pkgs.runCommand "s6-rc-compiled-db" {
        nativeBuildInputs = [pkgs.s6-rc];
      } ''
        s6-rc-compile $out ${s6SourceDir}
      '';

    # 配置
    environment.etc."s6-rc/compiled".source = config.system.build.s6-rc-db;
    environment.systemPackages = [
      pkgs.s6
      pkgs.s6-rc
    ];
  };
}
