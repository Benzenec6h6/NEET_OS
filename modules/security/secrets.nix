{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.neet.secrets;
  secCfg = config.neet.security.secrets;

  # 8進数文字列 ("0400", "0644" など) を 10進数整数 (256, 420 など) に変換するヘルパー
  octalToDecimal = str: let
    cleanStr = removePrefix "0o" (removePrefix "0" (toString str));
    chars = stringToCharacters (
      if cleanStr == ""
      then "0"
      else cleanStr
    );
    digitMap = {
      "0" = 0;
      "1" = 1;
      "2" = 2;
      "3" = 3;
      "4" = 4;
      "5" = 5;
      "6" = 6;
      "7" = 7;
    };
    step = acc: c:
      acc
      * 8
      + (
        digitMap.${c}
        or (throw "neet-secrets: 不正な8進数文字 '${c}' が mode '${toString str}' に含まれています")
      );
  in
    foldl' step 0 chars;

  secretOpts = {name, ...}: {
    options = {
      file = mkOption {
        type = types.path;
        description = "暗号化された .age ファイルへのパス (リポジトリ内の相対パスなど)";
      };

      path = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = ''
          平文ファイルの配置先絶対パス。
          null の場合はデフォルトで `/run/secrets/by-name/<name>` に配置されます。
        '';
      };

      owner = mkOption {
        type = types.str;
        default = "root";
        description = "配置される平文ファイルの所有ユーザー名 (または UID)";
      };

      group = mkOption {
        type = types.str;
        default = "root";
        description = "配置される平文ファイルの所有グループ名 (または GID)";
      };

      mode = mkOption {
        type = types.either types.str types.int;
        default = "0400";
        description = "ファイルパーミッション (例: \"0400\", \"0640\")";
      };

      env = {
        service = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "s6-envdir を適用する対象の s6-rc サービス名";
        };

        var = mkOption {
          type = types.nullOr types.str;
          default = null;
          description = "注入する環境変数名 (例: 'DATABASE_PASSWORD')";
        };
      };

      inInitrd = mkOption {
        type = types.bool;
        default = false;
        description = "Stage 1 (initrd 内) に含めるシークレットかどうか";
      };
    };
  };

  # neet-secret が読み込むマニフェスト JSON の生成
  manifestJson = pkgs.writeText "secrets-manifest.json" (builtins.toJSON {
    secrets =
      mapAttrsToList (name: s: {
        inherit name;
        encrypted_file = "${s.file}";
        owner = s.owner;
        group = s.group;
        mode =
          if isInt s.mode
          then s.mode
          else octalToDecimal s.mode;
        path = s.path;
        env =
          if s.env.service != null && s.env.var != null
          then {
            service = s.env.service;
            var = s.env.var;
          }
          else null;
      })
      cfg;
  });
in {
  options = {
    # 各シークレットの定義
    neet.secrets = mkOption {
      type = types.attrsOf (types.submodule secretOpts);
      default = {};
      example = literalExpression ''
        {
          "wg-private-key" = {
            file = ./secrets/wg.age;
            mode = "0400";
          };
          "db-password" = {
            file = ./secrets/db-pass.age;
            owner = "postgres";
            group = "postgres";
            env = {
              service = "postgresql";
              var = "POSTGRES_PASSWORD";
            };
          };
        }
      '';
      description = "neet-secret で管理・復号するシークレット一覧";
    };

    # シークレット管理機能全体のグローバル設定
    neet.security.secrets = {
      enable = mkOption {
        type = types.bool;
        default = cfg != {};
        description = "neet-secret によるシークレット復号機構を有効にするかどうか";
      };

      identityPath = mkOption {
        type = types.str;
        default = "/var/lib/sshd/ssh_host_ed25519_key";
        description = "復号に使用する SSH 秘密鍵のパス";
      };

      package = mkOption {
        type = types.package;
        default = config.system.build.neetSecret;
        defaultText = literalExpression "pkgs.inieet";
        description = "neet-secret バイナリを提供するパッケージ";
      };

      backend = mkOption {
        type = types.enum ["ssh" "tpm2"];
        default = "ssh";
        description = "シークレットの復号に使用するバックエンド";
      };

      tpmNvIndex = mkOption {
        type = types.str;
        default = "0x01500000";
        description = "TPM2 NVRAM のインデックス番号";
      };
    };
  };

  config = mkIf secCfg.enable {
    # 整合性チェック
    assertions =
      mapAttrsToList (name: s: {
        assertion = (s.env.service != null) == (s.env.var != null);
        message = "neet.secrets.${name}: env.service と env.var は両方指定するか、両方 null にする必要があります。";
      })
      cfg;

    # マニフェストを /etc に配置
    environment.etc."secrets-manifest.json".source = manifestJson;

    # s6-rc: ブート時にシークレットを復号する oneshot サービス
    system.s6-rc.services.secrets = {
      type = "oneshot";
      format = "sh";
      autoStart = true;

      # ホスト鍵が openssh 側で生成される場合は、その生成完了を待つ
      dependencies = optional (config.services.openssh.enable or false) "sshd-prepare";

      up = ''
        if [ -s "${secCfg.identityPath}" ]; then
          ${secCfg.package}/bin/neet-secret decrypt \
            --manifest /etc/secrets-manifest.json \
            --key ${escapeShellArg secCfg.identityPath} \
            --out-dir /run/secrets
        else
          echo "neet-secret: [warning] SSH host key ${secCfg.identityPath} not found. Skipping secret decryption."
        fi
      '';
      down = "";
    };

    system.s6-rc.services.secrets.up =
      if secCfg.backend == "tpm2"
      then ''
        ${secCfg.package}/bin/neet-secret decrypt \
          --tpm \
          --tpm-nv-index "${secCfg.tpmNvIndex}" \
          --manifest /etc/secrets-manifest.json \
          --out-dir /run/secrets
      ''
      else ''
        if [ -s "${secCfg.identityPath}" ]; then
          ${secCfg.package}/bin/neet-secret decrypt \
            --manifest /etc/secrets-manifest.json \
            --key ${escapeShellArg secCfg.identityPath} \
            --out-dir /run/secrets
        else
          echo "neet-secret: [warning] SSH host key ${secCfg.identityPath} not found."
        fi
      '';
  };
}
