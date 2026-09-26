{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.neet.security.privileges;
  pam_unix = "${pkgs.pam}/lib/security/pam_unix.so";
in {
  imports = [
    ./sudo-rs.nix
    ./doas.nix
  ];

  options.neet.security.privileges = {
    backend = lib.mkOption {
      type = lib.types.enum ["sudo-rs" "doas"];
      default = "sudo-rs";
      description = "特権昇格に使用するバックエンドの実装";
    };

    wheelNeedsPassword = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "wheel グループにパスワードを要求するか";
    };

    command = lib.mkOption {
      type = lib.types.str;
      description = "他のモジュールが使用すべき特権ラッパーへの絶対パス";
    };

    rules = lib.mkOption {
      type = with lib.types;
        listOf (submodule {
          options = {
            users = lib.mkOption {
              type = listOf (either str int);
              default = [];
            };
            groups = lib.mkOption {
              type = listOf (either str int);
              default = [];
            };
            command = lib.mkOption {
              type = str;
              default = "ALL";
            };
            args = lib.mkOption {
              type = str;
              default = "";
            };
            runAs = lib.mkOption {
              type = str;
              default = "ALL";
            };
            requirePassword = lib.mkOption {
              type = bool;
              default = true;
            };
          };
        });
      default = [];
      description = "システム全体で共有される特権昇格ルール";
    };
  };

  config = {
    # 選択されたバックエンドに応じた PAM サービスを自動定義
    neet.security.pam.services.${
      if cfg.backend == "sudo-rs"
      then "sudo"
      else "doas"
    } = ''
      auth      required    ${pam_unix} nullok
      account   required    ${pam_unix}
      password  required    ${pam_unix} sha512 shadow nullok
      session   required    ${pam_unix}
    '';
  };
}
