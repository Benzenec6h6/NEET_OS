{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.users;

  # /etc/shadow の1行を生成
  # フォーマット: username:password:lastchange:min:max:warn:inact:expire:flag
  mkShadowLine = name: u: let
    # パスワードが未設定の場合はアカウントをロック ('!') 状態にする
    passHash =
      if u.initialHashedPassword != null
      then u.initialHashedPassword
      else "!";
  in "${name}:${passHash}:19700:0:99999:7:::";
in {
  options.neet.users = mkOption {
    type = types.attrsOf (types.submodule {
      options = {
        initialHashedPassword = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "パスワードハッシュ (例: mkpasswd -m sha-512 で生成した文字列)";
        };
      };
    });
  };

  config = {
    # /etc/shadow の生成 (etc_syncer 等で 0600 / root:root のパーミッション制御が必要)
    environment.etc."shadow" = {
      text = concatStringsSep "\n" (mapAttrsToList mkShadowLine cfg) + "\n";
      mode = "0600";
    };
  };
}
