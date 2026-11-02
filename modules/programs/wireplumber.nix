{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.wireplumber;
  format = pkgs.formats.json {};

  runtimeUsers =
    lib.filterAttrs (
      _name: u:
        u.createRuntimeDir
        && u.uid >= 1000
    )
    config.neet.users;
in {
  options.programs.wireplumber = {
    enable = lib.mkEnableOption "WirePlumber session manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wireplumber;
      description = "The package to use for wireplumber.";
    };

    settings = lib.mkOption {
      type = format.type;
      default = {};
      description = "WirePlumber configuration options.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pipewire.enable = lib.mkDefault true;

    environment.systemPackages = [cfg.package];

    environment.etc."wireplumber/wireplumber.conf.d/99-neet.conf" = lib.mkIf (cfg.settings != {}) {
      source = format.generate "99-neet.conf" cfg.settings;
    };

    # ★ ユーザー s6-rc 側に純粋な "wireplumber" として登録！
    system.s6-rc.users =
      lib.mapAttrs (name: u: {
        services.wireplumber = {
          type = "longrun";
          dependencies = ["pipewire"];
          run = ''
            #!/bin/sh
            export XDG_STATE_HOME="$HOME/.local/state"
            exec ${cfg.package}/bin/wireplumber
          '';
        };
      })
      runtimeUsers;
  };
}
