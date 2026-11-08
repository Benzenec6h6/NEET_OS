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
  # ★ users の定義は削除してOK！
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

    environment.variables = {
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
    };

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

    # ★ sessionUsers を直接 mapAttrs で回す（循環参照ゼロ ＆ uid も直接取れる）
    system.s6-rc.users =
      mapAttrs (_username: user: {
        services.fcitx5 = {
          type = "longrun";
          autoStart = false; # top には含めない
          partOf = ["graphical-session"]; # ★ WM 起動時に連動
          envdirs = ["/run/user/${toString user.uid}/env"]; # ★ user.uid が直で使える！

          run = ''
            #!/bin/execlineb -P
            fdmove -c 2 1
            ${fcitx5Package}/bin/fcitx5
          '';
        };
      })
      config.neet.sessionUsers;
  };
}
