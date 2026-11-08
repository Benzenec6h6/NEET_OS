{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.i18n.inputMethod;
  fcitx5Cfg = cfg.fcitx5;

  # GUI設定ツールを除去した fcitx5-with-addons
  fcitx5Package = fcitx5Cfg.package.override {
    withConfigtool = false; # GUI設定ツールを排除
    addons = fcitx5Cfg.addons;
  };

  # NixOS公式に準じた INI 生成ヘルパー
  optionalIniFile = path: attrs:
    optionalAttrs (attrs != {}) {
      "xdg/fcitx5/${path}".text = generators.toINI {} attrs;
    };
in {
  options.i18n.inputMethod = {
    enable = mkEnableOption "fcitx5 input method under graphical-session";

    fcitx5 = {
      package = mkOption {
        type = types.package;
        # qt6Packages または kdePackages のものを指定
        default = pkgs.qt6Packages.fcitx5-with-addons;
        defaultText = literalExpression "pkgs.qt6Packages.fcitx5-with-addons";
        description = "The fcitx5-with-addons package to use.";
      };

      addons = mkOption {
        type = types.listOf types.package;
        default = [
          pkgs.fcitx5-mozc-ut
          pkgs.kdePackages.fcitx5-qt
          pkgs.fcitx5-gtk
        ];
        description = "List of fcitx5 addons.";
      };

      # NixOS 公式準拠の宣言的設定オプション
      settings = {
        inputMethod = mkOption {
          type = types.attrsOf types.anything;
          # デフォルトで日本語 (jp layout + mozc) を用意しつつ、上書き可能にする
          default = {
            "Groups/0" = {
              Name = "Default";
              "Default Layout" = "jp";
              DefaultIM = "mozc";
            };
            "Groups/0/Items/0".Name = "keyboard-jp";
            "Groups/0/Items/1".Name = "mozc";
            GroupOrder."0" = "Default";
          };
          description = "fcitx5 profile configuration (/etc/xdg/fcitx5/profile).";
        };

        globalOptions = mkOption {
          type = types.attrsOf types.anything;
          default = {};
          description = "fcitx5 global configuration (/etc/xdg/fcitx5/config).";
        };
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [fcitx5Package];

    environment.variables = {
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
    };

    # settings から動的に INI ファイルを生成
    environment.etc = foldl' recursiveUpdate {} [
      (optionalIniFile "profile" fcitx5Cfg.settings.inputMethod)
      (optionalIniFile "config" fcitx5Cfg.settings.globalOptions)
    ];

    # sessionUsers を直接 mapAttrs で回して s6-rc サービスを生成
    system.s6-rc.users =
      mapAttrs (_username: user: {
        services.fcitx5 = {
          type = "longrun";
          autoStart = false;
          partOf = ["graphical-session"];
          envdirs = ["/run/user/${toString user.uid}/env"];

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
