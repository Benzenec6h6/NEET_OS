{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nix-daemon;

  # nix.conf の生成
  nixConf = pkgs.writeText "nix.conf" ''
    # 新CLI & Flakes を有効化
    experimental-features = nix-command flakes

    # サンドボックスビルド用
    build-users-group = nixbld
    sandbox = true

    # root を信頼
    trusted-users = root

    # 公式バイナリキャッシュ
    substituters = https://cache.nixos.org/
    trusted-public-keys = cache.nixos.org-1:6NCHdD59X431o0gWypbMrAURkbJ16ZPMQFGspcDShjY=

    ${cfg.extraConfig}
  '';
in {
  options.services.nix-daemon = {
    enable = lib.mkEnableOption "Nix daemon service for NEET OS";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nix;
      description = "Nix package to use.";
    };

    nrBuildUsers = lib.mkOption {
      type = lib.types.int;
      default = 8;
      description = "Number of nixbld build users to create.";
    };

    extraConfig = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "Extra text to append to nix.conf.";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. nix コマンドをシステムパッケージに追加
    environment.systemPackages = [cfg.package];

    # 2. 設定ファイルの配置
    environment.etc."nix/nix.conf".source = nixConf;

    # 3. ログインシェル用の環境変数 (/etc/profile)
    #    Nix コマンドがデーモンを向くように設定
    environment.etc."profile.d/nix.sh".text = ''
      export NIX_REMOTE=daemon
      export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
    '';

    # 4. GID の定義 (neet.gids)
    neet.gids.nixbld = lib.mkDefault 30000;

    # 5. ビルドユーザー群の定義 (neet.users)
    neet.users = lib.listToAttrs (
      map (nr: {
        name = "nixbld${toString nr}";
        value = {
          uid = 30000 + nr;
          gid = 30000;
          home = "/var/empty";
          shell = "/bin/false";
          createHome = false;
          createRuntimeDir = false;
          description = "Nix build user ${toString nr}";
        };
      }) (lib.range 1 cfg.nrBuildUsers)
    );

    # 6. s6-rc サービス定義
    system.s6-rc.services.nix-daemon = {
      type = "longrun";
      # programs.resolvconf に修正
      dependencies = lib.optional config.programs.resolvconf.enable "resolvconf";
      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1

        # ソケットやテンポラリ用ディレクトリの準備
        foreground { mkdir -p -m 0755 /nix/var/nix/daemon-socket }
        foreground { mkdir -p -m 0755 /nix/var/nix/gcroots }
        foreground { mkdir -p -m 1777 /nix/var/nix/temproots }

        # 証明書環境変数を設定してデーモンを起動
        export SSL_CERT_FILE /etc/ssl/certs/ca-certificates.crt
        export CURL_CA_BUNDLE /etc/ssl/certs/ca-certificates.crt

        ${cfg.package}/bin/nix-daemon --daemon
      '';
    };
  };
}
