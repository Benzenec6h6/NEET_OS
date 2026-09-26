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

  # PAM 設定ファイルの共通ベース（Linux 標準的な unix 認証）
  defaultPamService = ''
    auth      required    ${pam_unix} nullok
    account   required    ${pam_unix}
    password  required    ${pam_unix} sha512 shadow nullok
    session   required    ${pam_unix}
  '';
in {
  options.neet.security.pam = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "/etc/pam.d 設定ファイルの生成を有効化するかどうか";
    };

    services = mkOption {
      type = types.attrsOf (types.submodule {
        options = {
          text = mkOption {
            type = types.str;
            default = defaultPamService;
            description = "PAM 設定内容。未指定時は標準 unix 認証が使われる";
          };
        };
      });
      default = {};
      example = literalExpression ''
        {
          # デフォルトの unix 認証を使う場合
          doas = {};
          # カスタム設定を渡す場合
          su.text = "auth sufficient ...";
        }
      '';
      description = "/etc/pam.d/<name> に配置するサービス定義";
    };
  };

  config = mkIf cfg.enable {
    # 組み込みサービスの登録（sudo は privileges 側に任せるためここから削除）
    neet.security.pam.services = {
      # 一般ログイン / Console
      login = {};

      # su コマンド用
      su.text = ''
        auth      sufficient  ${pam_rootok}
        ${defaultPamService}
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
      // (mapAttrs' (name: svc: nameValuePair "pam.d/${name}" {text = svc.text;}) cfg.services);
  };
}
