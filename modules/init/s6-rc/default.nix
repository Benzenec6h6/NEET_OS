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

      log = {
        enable = mkEnableOption "s6-log によるロガー (<name>-log) の自動生成";
        user = mkOption {
          type = types.str;
          default = "s6log";
          description = "s6-log を実行するユーザー。/etc/passwd に存在する必要がある。";
        };
        dirs = mkOption {
          type = types.listOf types.str;
          default = ["/var/log/${name}"];
          description = "事前に作成して user 所有にするログディレクトリ。args に現れるものを全て列挙する。";
        };
        args = mkOption {
          type = types.listOf types.str;
          default = ["n10" "s1000000" "T" "/var/log/${name}"];
          description = "s6-log に渡す引数 (制御ディレクティブ、選択行、logdir)。";
        };
      };

      logRun = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "ロガーの run スクリプトを丸ごと上書きする (log.* より優先)。longrun のみ有効。";
      };
    };
  };

  hasLog = svc: svc.type == "longrun" && (svc.log.enable || svc.logRun != null);

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
    # NOTE: 既存の assertions.nix が NixOS 互換の `assertions` を持つ前提
    assertions =
      (mapAttrsToList (n: s: {
          assertion = !(s.log.enable && s.type != "longrun");
          message = "s6-rc service '${n}': log.enable は longrun でのみ使えます";
        })
        cfg.services)
      ++ (mapAttrsToList (n: _: {
          assertion = !(cfg.services ? "${n}-log");
          message = "s6-rc service '${n}-log' は '${n}' のロガー名と衝突します";
        })
        (filterAttrs (_: hasLog) cfg.services));

    # ロガー用のデフォルトユーザー (log.user = "s6log" の場合)
    neet.users.s6log = {
      uid = mkDefault 980;
      gid = mkDefault 980;
      description = "s6-log logger";
      home = "/var/empty";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = false;
      createRuntimeDir = false;
    };

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
