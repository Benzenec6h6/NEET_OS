{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.system.s6-rc;
  s6lib = import ./lib.nix {inherit lib pkgs;};

  secretsEnabled = config.neet.security.secrets.enable or false;

  # loadSecrets を dependencies / envdirs に展開
  resolvedServices =
    mapAttrs (
      name: svc:
        svc
        // {
          dependencies = svc.dependencies ++ optional (svc.loadSecrets && secretsEnabled) "secrets";
          envdirs = svc.envdirs ++ optional svc.loadSecrets "/run/secrets/env/${name}";
        }
    )
    cfg.services;

  # 自作 CLI / 差分検知向けの JSON
  servicesJson = pkgs.writeText "s6-services.json" (
    builtins.toJSON (mapAttrs s6lib.extractMeta resolvedServices)
  );
in {
  imports = [./user.nix];

  options.system.s6-rc.services = s6lib.mkServicesOption "s6-rcサービス定義の集合";

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
      assertions = s6lib.mkAssertions "s6-rc" cfg.services;

      system.build.s6-rc-db = s6lib.buildDb "system" resolvedServices;

      environment.etc."s6-rc/services.json".source = servicesJson;
      environment.etc."s6-rc/compiled".source = config.system.build.s6-rc-db;
      environment.systemPackages = [pkgs.s6 pkgs.s6-rc];
    })
  ];
}
