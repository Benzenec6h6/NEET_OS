# s6-rc 周りの共通ヘルパー。
# default.nix / user.nix / build-source.nix から import して使う。
{
  lib,
  pkgs,
}:
with lib; let
  self = {
    # サービスオプション (service-options.nix) をまとめて公開
    serviceOpts = import ./service-options.nix {inherit lib pkgs;};

    # `services` オプションの定義を 1 箇所に集約
    mkServicesOption = description:
      mkOption {
        type = types.attrsOf (types.submodule self.serviceOpts);
        default = {};
        inherit description;
      };

    # ---- 命名規則 (logger / pipeline) ----
    hasLog = svc: svc.type == "longrun" && (svc.log.enable || svc.logRun != null);
    loggerName = name: "${name}-log";
    pipelineName = name: "${name}-pipeline";

    # top / bundle から参照するときの実体名 (ログ付きなら pipeline)
    entryName = name: svc:
      if self.hasLog svc
      then self.pipelineName name
      else name;

    # ---- 差分検知用メタデータ ----
    scriptHash = svc:
      if svc.type == "longrun"
      then builtins.hashString "sha256" svc.run
      else if svc.type == "oneshot"
      then builtins.hashString "sha256" "${svc.up}\n${svc.down}"
      else null;

    extractMeta = _name: svc: {
      inherit (svc) type dependencies autoStart partOf loadSecrets envdirs;
      scriptHash = self.scriptHash svc;
    };

    # ---- ソース組み立て + s6-rc-compile ----
    buildDb = name: services:
      pkgs.runCommand "s6-rc-db-${name}" {
        nativeBuildInputs = [pkgs.s6-rc];
      } ''
        s6-rc-compile $out ${import ./build-source.nix {
          inherit lib pkgs services;
          s6lib = self;
        }}
      '';
  };
in
  self
