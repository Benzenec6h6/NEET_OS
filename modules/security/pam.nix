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
      type = types.attrsOf types.str;
      default = {};
      example = literalExpression ''
        {
          login = "...";
          sudo = "...";
        }
      '';
      description = "追加・オーバーライドする /etc/pam.d/<service> のカスタム設定";
    };
  };

  config = lib.mkIf config.neet.security.pam.enable {
    # 1. デフォルトの PAM サービス設定を出力
    environment.etc =
      {
        # フォールバック用設定（定義がないサービス用）
        "pam.d/other".text = ''
          auth      required    ${pam_deny}
          account   required    ${pam_deny}
          password  required    ${pam_deny}
          session   required    ${pam_deny}
        '';

        # 一般ログイン / Console
        "pam.d/login".text = defaultPamService;

        # su コマンド用
        "pam.d/su".text = ''
          auth      sufficient  ${pam_rootok}
          ${defaultPamService}
        '';

        # sudo / sudo-rs 用
        "pam.d/sudo".text = defaultPamService;
      }
      # 2. ユーザーが custom services を定義していた場合に動的追加
      // (mapAttrs' (name: content: nameValuePair "pam.d/${name}" {text = content;}) cfg.services);
  };
}
