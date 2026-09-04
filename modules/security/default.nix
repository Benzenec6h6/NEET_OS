{
  config,
  pkgs,
  lib,
  ...
}:
with lib; {
  imports = [
    ./pam.nix
    ./polkit.nix
    ./shadow.nix
    ./wrappers.nix
    ./privileges
  ];

  options.neet.security = {
    enable = mkEnableOption "Enable security infrastructure (PAM, shadow, polkit)";
  };

  config = mkIf config.neet.security.enable {
    neet.security.wrappers = {
      # PAM がパスワード照合に使う必須ツール
      unix_chkpwd = {
        source = "${pkgs.pam}/sbin/unix_chkpwd";
        setuid = true;
        owner = "root";
        group = "root";
      };
    };
    # 必要なパッケージの導入
    environment.systemPackages = with pkgs; [
      pam
      shadow
      polkit
      sudo-rs
    ];

    # システム共通GIDの定義 (users.nix の neet.gids に追加)
    neet.gids = {
      shadow = lib.mkDefault 15;
      polkituser = lib.mkDefault 999;
    };

    # システムユーザーの定義 (users.nix の neet.users に追加)
    neet.users.polkituser = {
      uid = 999;
      gid = 999;
      description = "Polkit daemon user";
      createHome = false;
    };

    # PAM / Polkit の基本ファイル配置 (etc_syncer 経由)
    environment.etc = {
      "pam.d/other".text = ''
        auth     required       pam_deny.so
        account  required       pam_deny.so
        password required       pam_deny.so
        session  required       pam_deny.so
      '';
      "polkit-1/rules.d/50-default.rules".text = ''
        polkit.addAdminRule(function(action, subject) {
            return ["unix-group:wheel"];
        });
      '';
    };
  };
}
