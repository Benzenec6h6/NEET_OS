{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.neet.secrets;
  secCfg = config.neet.security.secrets;

  editorScriptText =
    replaceStrings
    ["@defaultRecipients@" "@defaultIdentity@"]
    [
      (concatMapStringsSep " " (k: escapeShellArg "-r ${k}") secCfg.editor.publicKeys)
      (escapeShellArg secCfg.editor.defaultIdentity)
    ]
    (builtins.readFile ./neet-secret-edit.sh);

  # ★ runtimeInputs を使って堅牢なパッケージにする
  secretEditorPkg = pkgs.writeShellApplication {
    name = "neet-secret-edit";

    runtimeInputs = [
      pkgs.age
      pkgs.coreutils
      pkg.vim
    ];

    checkPhase = "";
    text = editorScriptText;
  };

  tpmEnrollPkg = pkgs.writeShellApplication {
    name = "neet-tpm-enroll";

    runtimeInputs = with pkgs; [
      tpm2-tools
      age
      coreutils
      gnugrep
      util-linux # mount, umount 用
    ];

    text = builtins.readFile ./neet-tpm-enroll.sh;
  };

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

  # 各シークレットの定義スキーマ
  secretOpts = {name, ...}: {
    options = {
      file = mkOption {
        type = types.path;
        description = "暗号化された .age ファイルへのパス (リポジトリ内の相対パスなど)";
      };

      inInitrd = mkOption {
        type = types.bool;
        default = false;
        description = "Stage 1 (LUKS 解錠前) の initrd 内に含めるシークレットかどうか";
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
    };
  };

  # (inInitrd = true のものは Stage 1 用なので、Stage 2 のマニフェストからは除外しても構いませんが、含んでいても問題ありません)
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
      (filterAttrs (_: s: !s.inInitrd) cfg);
  });
in {
  options = {
    # 各シークレットの定義 (元のまま secretOpts を渡すだけ)
    neet.secrets = mkOption {
      type = types.attrsOf (types.submodule secretOpts);
      default = {};
      example = literalExpression ''
        {
          "luks-root-key" = {
            file = ./secrets/luks-root.age;
            inInitrd = true;
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

      tools = {
        enable = mkOption {
          type = types.bool;
          default = false;
          description = "neet-secret-edit や neet-tpm-enroll などの管理用 CLI を環境に導入するかどうか";
        };
      };

      backend = mkOption {
        type = types.enum ["ssh" "tpm2"];
        default = "ssh";
        description = "復号に使用する鍵ソース (ssh: SSHホスト鍵, tpm2: TPM 2.0 NVRAM)";
      };

      # backend = "ssh" の場合に使用
      identityPath = mkOption {
        type = types.str;
        default = "/var/lib/sshd/ssh_host_ed25519_key";
        description = "backend = 'ssh' の時に使用する SSH 秘密鍵のパス";
      };

      package = mkOption {
        type = types.package;
        default = config.system.build.neetSecret;
        defaultText = literalExpression "config.system.build.neetSecret";
        description = "neet-secret バイナリを提供するパッケージ";
      };

      editor = {
        # 暗号化の受信者として登録する公開鍵リスト
        publicKeys = mkOption {
          type = types.listOf types.str;
          default = [];
          example = [
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5..." # 開発者の SSH 鍵
            "age1ql3z7hjyfk5pw7k9..." # TPM 用の age 公開鍵
          ];
          description = "シークレット暗号化時に合鍵として含める公開鍵リスト";
        };

        # 開発者が手元で復号するために使う秘密鍵のデフォルトパス
        defaultIdentity = mkOption {
          type = types.str;
          default = "$HOME/.ssh/id_ed25519";
          description = "手元で編集時に復号用として使うデフォルト秘密鍵パス";
        };
      };
    };
  };

  config = mkMerge [
    # ① 復号サービス本体 (シークレットが定義されている、または明示的に enable の時だけ動く)
    (mkIf secCfg.enable {
      assertions =
        mapAttrsToList (name: s: {
          assertion = (s.env.service != null) == (s.env.var != null);
          message = "neet.secrets.${name}: env.service と env.var は両方指定するか、両方 null にする必要があります。";
        })
        cfg;

      environment.etc."secrets-manifest.json".source = manifestJson;

      system.s6-rc.services.secrets = {
        type = "oneshot";
        format = "sh";
        autoStart = true;
        dependencies = optional (secCfg.backend == "ssh" && (config.services.openssh.enable or false)) "sshd-prepare";

        up =
          if secCfg.backend == "tpm2"
          then ''
            ${secCfg.package}/bin/neet-secret decrypt \
              --manifest /etc/secrets-manifest.json \
              --tpm \
              --out-dir /run/secrets
          ''
          else ''
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
    })

    # ② CLI ツール群 (復号サービス有効時、または明示的に tools.enable = true の時に導入)
    (mkIf (secCfg.enable || secCfg.tools.enable) {
      environment.systemPackages = [secretEditorPkg tpmEnrollPkg];
    })
  ];
}
