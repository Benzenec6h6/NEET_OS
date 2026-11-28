{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.i18n.inputMethod;
  fcitx5Cfg = cfg.fcitx5;

  fcitx5Package = fcitx5Cfg.package.override {
    withConfigtool = false;
    addons = fcitx5Cfg.addons;
  };

  optionalIniFile = path: attrs:
    optionalAttrs (attrs != {}) {
      "xdg/fcitx5/${path}".text = generators.toINI {} attrs;
    };

  anyUserEnabled = cfg.enable || any (u: u.programs.fcitx5.enable) (attrValues config.neet.users);
in {
  options = {
    # ─── システム共通設定 ───
    i18n.inputMethod = {
      enable = mkEnableOption "fcitx5 input method under graphical-session";

      fcitx5 = {
        package = mkOption {
          type = types.package;
          default = pkgs.qt6Packages.fcitx5-with-addons;
          defaultText = literalExpression "pkgs.qt6Packages.fcitx5-with-addons";
          description = "使用する fcitx5-with-addons パッケージ";
        };

        addons = mkOption {
          type = types.listOf types.package;
          default = [
            pkgs.fcitx5-mozc-ut
            pkgs.kdePackages.fcitx5-qt
            pkgs.fcitx5-gtk
          ];
          description = "追加する fcitx5 アドオン一覧";
        };

        settings = {
          inputMethod = mkOption {
            type = types.attrsOf types.anything;
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
            description = "システム共通の fcitx5 profile 設定 (/etc/xdg/fcitx5/profile)";
          };

          globalOptions = mkOption {
            type = types.attrsOf types.anything;
            default = {};
            description = "システム共通の fcitx5 global 設定 (/etc/xdg/fcitx5/config)";
          };
        };
      };
    };

    # ─── ユーザーごとの設定・s6 サービス ───
    neet.users = mkOption {
      type = types.attrsOf (types.submodule ({
        name,
        config,
        ...
      }: let
        userCfg = config.programs.fcitx5;
      in {
        options.programs.fcitx5 = {
          enable = mkOption {
            type = types.bool;
            default = cfg.enable && config.isSessionUser;
            description = "ユーザー '${name}' で fcitx5 を有効にするか";
          };

          settings = {
            inputMethod = mkOption {
              type = types.attrsOf types.anything;
              default = fcitx5Cfg.settings.inputMethod;
              description = "ユーザー固有の profile 設定 (~/.config/fcitx5/profile)";
            };

            globalOptions = mkOption {
              type = types.attrsOf types.anything;
              default = fcitx5Cfg.settings.globalOptions;
              description = "ユーザー固有の global 設定 (~/.config/fcitx5/config)";
            };
          };
        };

        config = mkIf userCfg.enable {
          xdg.configFile = foldl' recursiveUpdate {} [
            (optionalAttrs (userCfg.settings.inputMethod != {}) {
              "fcitx5/profile".text = generators.toINI {} userCfg.settings.inputMethod;
            })
            (optionalAttrs (userCfg.settings.globalOptions != {}) {
              "fcitx5/config".text = generators.toINI {} userCfg.settings.globalOptions;
            })
          ];

          # ★ s6.services に定義
          s6.services.fcitx5 = {
            type = "longrun";
            autoStart = false;
            partOf = ["graphical-session"];
            run = ''
              #!/bin/sh
              exec ${fcitx5Package}/bin/fcitx5
            '';
          };
        };
      }));
    };
  };

  config = mkIf anyUserEnabled {
    environment.systemPackages = [fcitx5Package];

    environment.variables = {
      QT_IM_MODULE = "fcitx";
      XMODIFIERS = "@im=fcitx";
    };

    environment.etc = foldl' recursiveUpdate {} [
      (optionalIniFile "profile" fcitx5Cfg.settings.inputMethod)
      (optionalIniFile "config" fcitx5Cfg.settings.globalOptions)
    ];
  };
}
