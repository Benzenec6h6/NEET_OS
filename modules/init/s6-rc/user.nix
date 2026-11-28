{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  s6lib = import ./lib.nix {inherit lib pkgs;};

  userServicesOpts = {name, ...}: let
    userDef = config.neet.users.${name} or {};
    # users.nix の仕様(未指定時 null)に合わせて安全にホームパスを確定
    userHome =
      if (userDef.home or null) != null
      then userDef.home
      else "/home/${name}";
  in {
    options.services = s6lib.mkUserServicesOption name userHome "ユーザー '${name}' 専用の s6-rc サービス定義";

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
            source = s6lib.buildUserDb "user-${name}" userCfg.services;
          }
      )
      activeUserServices
      // {"s6-rc/users-services.json".source = usersServicesJson;};

    environment.systemPackages = [
      (pkgs.writeShellApplication {
        name = "neet-user-s6-sync";
        runtimeInputs = [pkgs.coreutils pkgs.s6-rc];
        text = builtins.readFile ./neet-user-s6-sync.sh;
      })
    ];
  };
}
