{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.users;

  # 初期 /etc/shadow の行生成
  # initialHashedPassword があればそれを使い、なければ "!" (ロック)
  mkShadowLine = name: u: let
    passHash =
      if u.initialHashedPassword != null
      then u.initialHashedPassword
      else "!";
  in "${name}:${passHash}:19700:0:99999:7:::";

  # シークレットからハッシュを注入する必要があるユーザー一覧
  usersWithSecret = filterAttrs (_: u: u.hashedPasswordSecret != null) cfg;

  # s6-rc で実行する注入スクリプト
  applyScript = concatStringsSep "\n" (
    mapAttrsToList (name: u: ''
      _secret_file="/run/secrets/by-name/${u.hashedPasswordSecret}"
      if [ -s "$_secret_file" ]; then
        _hash=$(cat "$_secret_file")
        # sed の区切り文字にはハッシュに含まれない | を使用
        sed -i "s|^${name}:[^:]*:|${name}:''${_hash}:|" /etc/shadow
      else
        echo "shadow: [warning] Secret for user ${name} not found at $_secret_file"
      fi
    '')
    usersWithSecret
  );
in {
  config = {
    environment.systemPackages = [pkgs.shadow];
    neet.gids.shadow = lib.mkDefault 15;

    # 1. ベースとなる /etc/shadow の生成
    environment.etc."shadow" = {
      text = concatStringsSep "\n" (mapAttrsToList mkShadowLine cfg) + "\n";
      mode = "0600";
    };

    # 2. シークレットを使うユーザーが存在する場合のみ、s6-rc ワンショットサービスを定義
    system.s6-rc.services = mkIf (usersWithSecret != {}) {
      apply-shadow-secrets = {
        type = "oneshot";
        format = "sh";
        autoStart = true;
        # neet-secret による復号完了を待ってから動かす
        dependencies = ["secrets"];

        up = ''
          # /etc/shadow が Nix store へのシンボリックリンクだった場合、
          # 実体コピーに置き換えて書き込み可能にする (安全策)
          if [ -L /etc/shadow ]; then
            cp --remove-destination "$(readlink -f /etc/shadow)" /etc/shadow
            chmod 0600 /etc/shadow
          fi

          ${applyScript}
        '';

        down = "";
      };
    };
  };
}
