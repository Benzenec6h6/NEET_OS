{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.security.pam;

  pam_unix = "${pkgs.pam}/lib/security/pam_unix.so";
  pam_deny = "${pkgs.pam}/lib/security/pam_deny.so";
  pam_rootok = "${pkgs.pam}/lib/security/pam_rootok.so";

  # PAM 各スタックのルールを組み立てるサブモジュール
  serviceModule = {
    options = {
      # 行単位での追加フック
      extraAuth = mkOption {
        type = types.lines;
        default = "";
        description = "auth スタックに追加するルール";
      };
      extraAccount = mkOption {
        type = types.lines;
        default = "";
        description = "account スタックに追加するルール";
      };
      extraPassword = mkOption {
        type = types.lines;
        default = "";
        description = "password スタックに追加するルール";
      };
      extraSession = mkOption {
        type = types.lines;
        default = "";
        description = "session スタックに追加するルール";
      };

      # 完全に全体を上書きしたい場合のみ使用
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "設定ファイル全体を上書きする場合の内容";
      };
    };
  };

  # デフォルトの PAM サービス生成ロジック
  mkPamService = name: svc:
    if svc.text != null
    then svc.text
    else ''
      # PAM configuration for ${name}
      auth      required    ${pam_unix} nullok
      ${svc.extraAuth}

      account   required    ${pam_unix}
      ${svc.extraAccount}

      password  required    ${pam_unix} sha512 shadow nullok
      ${svc.extraPassword}

      session   required    ${pam_unix}
      ${svc.extraSession}
    '';
in {
  options.neet.security.pam = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "/etc/pam.d 設定ファイルの生成を有効化するかどうか";
    };

    services = mkOption {
      type = types.attrsOf (types.submodule serviceModule);
      default = {};
      description = "/etc/pam.d/<name> に配置するサービス定義";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.pam];

    neet.security.wrappers.unix_chkpwd = {
      source = "${pkgs.pam}/sbin/unix_chkpwd";
      setuid = true;
      owner = "root";
      group = "root";
    };

    # 組み込みサービスのベース登録（外部依存の記述はゼロ）
    neet.security.pam.services = {
      # 一般コンソールログイン
      login = {};

      # su コマンド用（rootok のみ特別扱い）
      su.text = ''
        auth      sufficient  ${pam_rootok}
        auth      required    ${pam_unix} nullok
        account   required    ${pam_unix}
        password  required    ${pam_unix} sha512 shadow nullok
        session   required    ${pam_unix}
      '';

      # passwd コマンド用
      passwd.text = ''
        password  sufficient  ${pam_unix} sha512 shadow nullok
        password  required    ${pam_deny}
      '';
    };

    # /etc/pam.d/ の生成
    environment.etc =
      {
        # フォールバック用設定（未定義サービス用）
        "pam.d/other".text = ''
          auth      required    ${pam_deny}
          account   required    ${pam_deny}
          password  required    ${pam_deny}
          session   required    ${pam_deny}
        '';
      }
      // (mapAttrs' (name: svc:
        nameValuePair "pam.d/${name}" {
          text = mkPamService name svc;
        })
      cfg.services);
  };
}
