{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.system.s6-rc;

  # ★ 変更点①: サービスオプションを共通ファイルからインポート
  serviceOpts = import ./service-options.nix {inherit lib pkgs;};

  resolvedServices =
    mapAttrs (
      name: svc:
        svc
        // {
          dependencies =
            svc.dependencies
            ++ optional (svc.loadSecrets && (config.neet.security.secrets.enable or false)) "secrets";
          envdirs =
            svc.envdirs
            ++ optional svc.loadSecrets "/run/secrets/env/${name}";
        }
    )
    cfg.services;

  # ソースディレクトリの組み立て
  s6SourceDir = import ./build-source.nix {
    inherit lib pkgs;
    services = resolvedServices;
  };

  # メタデータ抽出関数
  extractMeta = name: svc: {
    inherit (svc) type dependencies autoStart partOf loadSecrets envdirs;
    # スクリプト本文の変更を検知するためのハッシュ
    scriptHash =
      if svc.type == "longrun"
      then builtins.hashString "sha256" svc.run
      else if svc.type == "oneshot"
      then builtins.hashString "sha256" "${svc.up}\n${svc.down}"
      else null;
  };

  # 自作 CLI / 差分検知向けの JSON
  servicesJson = pkgs.writeText "s6-services.json" (
    builtins.toJSON (mapAttrs extractMeta resolvedServices)
  );
in {
  # ★ 変更点②: user.nix を読み込む
  imports = [
    ./user.nix
  ];

  options.system.s6-rc = {
    services = mkOption {
      type = types.attrsOf (types.submodule serviceOpts);
      default = {};
      description = "s6-rcサービス定義の集合";
    };
  };

  config = mkMerge [
    {
      neet.users.s6log = {
        uid = mkDefault 980;
        gid = mkDefault 980;
        description = "s6-log logger";
        home = "/var/empty";
        shell = "${pkgs.coreutils}/bin/false";
        createHome = false;
        createRuntimeDir = false;
      };
    }

    (mkIf (cfg.services != {}) {
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

      # コンパイル済みDBの構築
      system.build.s6-rc-db =
        pkgs.runCommand "s6-rc-compiled-db" {
          nativeBuildInputs = [pkgs.s6-rc];
        } ''
          s6-rc-compile $out ${s6SourceDir}
        '';

      # JSON をビルド成果物と /etc に登録
      system.build.s6-services-json = servicesJson;
      environment.etc."s6-rc/services.json".source = servicesJson;

      # 配置
      environment.etc."s6-rc/compiled".source = config.system.build.s6-rc-db;
      environment.systemPackages = [
        pkgs.s6
        pkgs.s6-rc
      ];
    })
  ];
}
