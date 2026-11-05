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

  activeUserServices = filterAttrs (_name: u: u.services != {}) config.system.s6-rc.users;
in {
  options.system.s6-rc.users = mkOption {
    type = types.attrsOf (types.submodule userServicesOpts);
    default = {};
    description = "宣言されたユーザー単位の s6-rc サービス定義群";
  };

  config = mkIf (activeUserServices != {}) {
    # コンパイル済み DB のみを配置
    environment.etc =
      mapAttrs' (
        name: userCfg:
          nameValuePair "s6-rc/users/${name}/compiled" {
            source = mkUserDb name userCfg;
          }
      )
      activeUserServices;
  };
}
