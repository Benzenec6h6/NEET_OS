{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  serviceOpts = import ./service-options.nix {inherit lib pkgs;};

  userServicesOpts = {name, ...}: {
    options = {
      services = mkOption {
        type = types.attrsOf (types.submodule serviceOpts);
        default = {};
        description = "ユーザー '${name}' 専用の s6-rc サービス定義";
      };
    };
  };

  # ユーザーごとの live 定義ディレクトリパス
  userLiveDefDir = username: let
    uid = toString config.neet.users.${username}.uid;
  in "/run/user/${uid}/service-definitions";

  # ユーザーごとのコンパイル済み s6-rc-db を生成
  mkUserDb = username: userCfg: let
    s6SourceDir = import ./build-source.nix {
      inherit lib pkgs;
      services = userCfg.services;
      liveDefDir = userLiveDefDir username;
    };
  in
    pkgs.runCommand "s6-rc-user-db-${username}" {
      nativeBuildInputs = [pkgs.s6-rc];
    } ''
      s6-rc-compile $out ${s6SourceDir}
    '';

  # restartOnUpdate = false 用の実体スクリプト群を束ねたディレクトリ
  mkUserDefinitions = username: userCfg: let
    # 各サービスの実際の run スクリプトを linkFarm にする
    defs = mapAttrsToList (name: svc: {
      name = "${name}/run";
      path = pkgs.writeScript "${name}-real-run" svc.run;
    }) (filterAttrs (_: svc: svc.type == "longrun") userCfg.services);
  in
    pkgs.linkFarm "s6-user-defs-${username}" defs;

  activeUserServices = filterAttrs (_name: u: u.services != {}) config.system.s6-rc.users;
in {
  options.system.s6-rc.users = mkOption {
    type = types.attrsOf (types.submodule userServicesOpts);
    default = {};
    description = "宣言されたユーザー単位の s6-rc サービス定義群";
  };

  config = mkIf (activeUserServices != {}) {
    environment.etc = mkMerge [
      # 1. コンパイル済み DB の配置
      (mapAttrs' (
          name: userCfg:
            nameValuePair "s6-rc/users/${name}/compiled" {
              source = mkUserDb name userCfg;
            }
        )
        activeUserServices)

      # 2. 実体スクリプト群の配置
      (mapAttrs' (
          name: userCfg:
            nameValuePair "s6-rc/users/${name}/definitions" {
              source = mkUserDefinitions name userCfg;
            }
        )
        activeUserServices)
    ];
  };
}
