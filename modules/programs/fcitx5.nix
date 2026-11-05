{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.fcitx5;

  # アドオンをまとめたバイナリ（GUI設定ツールは不要）
  fcitx5Package = pkgs.fcitx5-with-addons.override {
    addons = cfg.addons;
  };

  # s6 サービスを有効化するユーザー一覧
  users = attrNames config.system.s6-rc.users;
in {
  options.programs.fcitx5 = {
    enable = mkEnableOption "fcitx5 input method under graphical-session";

    addons = mkOption {
      type = types.listOf types.package;
      default = [
        pkgs.fcitx5-mozc-ut
        pkgs.kdePackages.fcitx5-qt
        pkgs.fcitx5-gtk
      ];
      description = "List of fcitx5 addons";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [fcitx5Package];

    # アプリ側が fcitx5 を探すための環境変数
    environment.sessionVariables = {
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
    };

    # GUIツール不要！静的に日本語+Mozcを設定
    environment.etc."xdg/fcitx5/profile".text = ''
      [Groups/0]
      Name=Default
      Default Layout=jp
      DefaultIM=mozc

      [Groups/0/Items/0]
      Name=keyboard-jp

      [Groups/0/Items/1]
      Name=mozc

      [GroupOrder]
      0=Default
    '';

    # ユーザー s6-rc への登録
    system.s6-rc.users = genAttrs users (username: let
      uid = toString config.neet.users.${username}.uid;
    in {
      services.fcitx5 = {
        type = "longrun";
        autoStart = false; # top には含めない
        partOf = ["graphical-session"]; # ★ WM 起動時に連動させる！
        envdirs = ["/run/user/${uid}/env"]; # ★ display-manager が作った envdir を読む

        # フォアグラウンドで常駐
        run = ''
          #!/bin/execlineb -P
          fdmove -c 2 1
          ${fcitx5Package}/bin/fcitx5
        '';
      };
    });
  };
}
