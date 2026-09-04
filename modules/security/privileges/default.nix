{
  config,
  lib,
  ...
}: let
  cfg = config.neet.security.privileges;
in {
  imports = [
    ./sudo-rs.nix
  ];

  options.neet.security.privileges = {
    backend = lib.mkOption {
      type = lib.types.enum ["sudo-rs" "sudo" "doas"];
      default = "sudo-rs"; # デフォルトは安全な sudo-rs
      description = "特権昇格に使用するバックエンドの実装";
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

    command = lib.mkOption {
      type = lib.types.str;
      readOnly = true;
      description = "他のモジュールが使用すべき特権ラッパーへの絶対パス";
    };
  };

  config = {
    # どのバックエンドを選んでも、利用側はここを参照する
    neet.security.privileges.command = "/run/wrappers/bin/sudo";
  };
}
