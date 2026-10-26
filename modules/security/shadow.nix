{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.users;

  mkShadowLine = name: u: let
    passHash =
      if u.initialHashedPassword != null
      then u.initialHashedPassword
      else "!";
  in "${name}:${passHash}:19700:0:99999:7:::";
in {
  config = {
    # 1. パッケージ
    environment.systemPackages = [pkgs.shadow];

    # 2. shadow GID 定義（security/default.nix から移動）
    neet.gids.shadow = lib.mkDefault 15;

    # 3. /etc/shadow の生成
    environment.etc."shadow" = {
      text = concatStringsSep "\n" (mapAttrsToList mkShadowLine cfg) + "\n";
      mode = "0600";
    };
  };
}
