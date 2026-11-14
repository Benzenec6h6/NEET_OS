{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  s6lib = import ./lib.nix {inherit lib pkgs;};

  userServicesOpts = {name, ...}: {
    options.services = s6lib.mkServicesOption "ユーザー '${name}' 専用の s6-rc サービス定義";

    # graphical-session は所属 0 でも常に空バンドルとして存在させる
    config.services.graphical-session = {
      type = mkDefault "bundle";
      autoStart = mkDefault false;
    };
  };

  hasUserServices = u:
    (removeAttrs u.services ["graphical-session"])
    != {}
    || (u.services ? graphical-session && u.services.graphical-session.contents != []);

  # 空のユーザー DB も出力したい場合は filterAttrs (_: u: u.services != {}) に変える
  activeUserServices = filterAttrs (_: hasUserServices) config.system.s6-rc.users;

  extractUserMeta = username: userCfg: let
    userDef = config.neet.users.${username} or null;
  in {
    uid = userDef.uid or null;
    gid = userDef.gid or null;
    services = mapAttrs s6lib.extractMeta userCfg.services;
  };

  usersServicesJson = pkgs.writeText "s6-users-services.json" (
    builtins.toJSON (mapAttrs extractUserMeta activeUserServices)
  );
in {
  options.system.s6-rc.users = mkOption {
    type = types.attrsOf (types.submodule userServicesOpts);
    default = {};
    description = "宣言されたユーザー単位の s6-rc サービス定義群";
  };

  config = mkIf (activeUserServices != {}) {
    assertions = concatLists (mapAttrsToList (
        name: userCfg:
          s6lib.mkAssertions "s6-rc (user:${name})" userCfg.services
      )
      activeUserServices);

    environment.etc =
      mapAttrs' (
        name: userCfg:
          nameValuePair "s6-rc/users/${name}/compiled" {
            source = s6lib.buildDb "user-${name}" userCfg.services;
          }
      )
      activeUserServices
      // {"s6-rc/users-services.json".source = usersServicesJson;};
  };
}
