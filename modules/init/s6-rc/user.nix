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

  # ユーザーごとのコンパイル済み s6-rc-db を生成
  mkUserDb = username: userCfg: let
    s6SourceDir = import ./build-source.nix {
      inherit lib pkgs;
      services = userCfg.services;
    };
  in
    pkgs.runCommand "s6-rc-user-db-${username}" {
      nativeBuildInputs = [pkgs.s6-rc];
    } ''
      s6-rc-compile $out ${s6SourceDir}
    '';

  # 各ユーザーのメタデータを集約
  extractUserMeta = username: userCfg: let
    userDef = config.neet.users.${username} or null;
  in {
    uid =
      if userDef != null
      then userDef.uid
      else null;
    gid =
      if userDef != null
      then userDef.gid
      else null;
    services =
      mapAttrs (name: svc: {
        inherit (svc) type dependencies autoStart partOf;
        scriptHash =
          if svc.type == "longrun"
          then builtins.hashString "sha256" svc.run
          else if svc.type == "oneshot"
          then builtins.hashString "sha256" "${svc.up}\n${svc.down}"
          else null;
      })
      userCfg.services;
  };

  usersServicesJson = pkgs.writeText "s6-users-services.json" (builtins.toJSON (
    mapAttrs extractUserMeta activeUserServices
  ));

  activeUserServices = filterAttrs (_name: u: u.services != {}) config.system.s6-rc.users;
in {
  options.system.s6-rc.users = mkOption {
    type = types.attrsOf (types.submodule userServicesOpts);
    default = {};
    description = "宣言されたユーザー単位の s6-rc サービス定義群";
  };

  config = mkIf (activeUserServices != {}) {
    environment.etc =
      (mapAttrs' (
          name: userCfg:
            nameValuePair "s6-rc/users/${name}/compiled" {
              source = mkUserDb name userCfg;
            }
        )
        activeUserServices)
      // {
        "s6-rc/users-services.json".source = usersServicesJson;
      };

    system.build.s6-users-services-json = usersServicesJson;
  };
}
