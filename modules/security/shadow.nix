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

  # コマンドのピン留め (セキュリティ担保と PATH 非依存化)
  core = pkgs.coreutils;
  sed = "${pkgs.gnused}/bin/sed";

  # s6-rc で実行する注入スクリプト
  applyScript = concatStringsSep "\n" (
    mapAttrsToList (name: u: ''
      _secret_file="/run/secrets/by-name/${u.hashedPasswordSecret}"
      if [ -s "$_secret_file" ]; then
        # ★ 改善: cat を絶対パス化
        _hash=$(${core}/bin/cat "$_secret_file")
        # ★ 改善: sed を絶対パス化 (区切り文字は | )
        ${sed} -i "s|^${name}:[^:]*:|${name}:''${_hash}:|" /etc/shadow
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
          # 実体コピーに安全に置き換えて書き込み可能にする
          if [ -L /etc/shadow ]; then
            # ★ 改善: リンク先を確定パスの readlink で解決
            _store_target=$(${core}/bin/readlink -f /etc/shadow)

            # ★ 改善: 一時ファイルを作成して権限を 0600 に設定してから mv で不可分に入れ替える
            # (一瞬たりとも /etc/shadow が消えたり不用意な権限で露出するのを防ぐ)
            ${core}/bin/cp "$_store_target" /etc/shadow.tmp
            ${core}/bin/chmod 0600 /etc/shadow.tmp
            ${core}/bin/mv -f /etc/shadow.tmp /etc/shadow
          fi

          ${applyScript}
        '';

        down = "";
      };
    };
  };
}
