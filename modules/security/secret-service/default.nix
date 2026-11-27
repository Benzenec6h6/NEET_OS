{
  config,
  lib,
  ...
}:
with lib; {
  imports = [
    ./oo7.nix
    ./gnome-keyring.nix
  ];

  config = {
    # システム全体で oo7 と gnome-keyring が同時に有効化されていないかチェック
    assertions = [
      {
        assertion = !(config.neet.security.oo7.enable && config.neet.security.gnome-keyring.enable);
        message = "Secret Service プロバイダとして 'oo7' と 'gnome-keyring' が同時に有効化されています。どちらか一方のみを選択してください。";
      }
    ];
  };
}
