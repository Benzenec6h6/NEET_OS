{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.wireplumber;
  format = pkgs.formats.json {};
in {
  options.programs.wireplumber = {
    enable = mkEnableOption "WirePlumber session manager";

    package = mkOption {
      type = types.package;
      default = pkgs.wireplumber;
      description = "The package to use for wireplumber.";
    };

    settings = mkOption {
      type = format.type;
      default = {};
      description = "システム共通の WirePlumber 設定 (SPA-JSON)";
    };
  };

  # ─── ユーザーごとの設定・s6 サービス ───
  options.neet.users = mkOption {
    type = types.attrsOf (types.submodule ({
      name,
      config,
      ...
    }: let
      userCfg = config.services.wireplumber;
    in {
      # ユーザー側は自然に services.wireplumber として宣言可能
      options.services.wireplumber = {
        enable = mkOption {
          type = types.bool;
          default = cfg.enable && config.isSessionUser;
          description = "ユーザー '${name}' で WirePlumber を起動するか";
        };

        settings = mkOption {
          type = format.type;
          default = {};
          description = "ユーザー固有の WirePlumber 設定 (~/.config/wireplumber/wireplumber.conf.d/99-user.conf)";
        };
      };

      config = mkIf userCfg.enable {
        xdg.configFile."wireplumber/wireplumber.conf.d/99-user.conf" = mkIf (userCfg.settings != {}) {
          source = format.generate "99-user.conf" userCfg.settings;
        };

        # ★ s6.services に定義
        s6.services.wireplumber = {
          type = "longrun";
          dependencies = ["pipewire"];
          log.enable = true;
          run = ''
            #!/bin/sh
            export XDG_STATE_HOME="$HOME/.local/state"
            exec ${cfg.package}/bin/wireplumber
          '';
        };
      };
    }));
  };

  config = mkIf cfg.enable {
    services.pipewire.enable = mkDefault true;

    environment.systemPackages = [cfg.package];

    environment.etc."wireplumber/wireplumber.conf.d/99-neet.conf" = mkIf (cfg.settings != {}) {
      source = format.generate "99-neet.conf" cfg.settings;
    };
  };
}
