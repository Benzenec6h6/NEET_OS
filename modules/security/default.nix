{
  config,
  pkgs,
  lib,
  ...
}:
with lib; {
  imports = [
    ./ca.nix
    ./pam.nix
    ./polkit.nix
    ./shadow.nix
    ./wrappers.nix
    ./privileges
  ];

  options.neet.security = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Enable security infrastructure (PAM, shadow, polkit)";
    };
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
    };
  };
}
