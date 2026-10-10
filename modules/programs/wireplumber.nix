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

  wireplumberServices =
    lib.mapAttrs' (
      name: u: let
        uidStr = toString u.uid;
        runtimeDir = "/run/user/${uidStr}";
        busAddress = "unix:path=${runtimeDir}/bus";
      in
        lib.nameValuePair "wireplumber-${name}" {
          type = "longrun";
          dependencies = ["pipewire-${name}" "dbus-user-${name}"];
          run = ''
            #!/bin/sh
            export XDG_RUNTIME_DIR="${runtimeDir}"
            export DBUS_SESSION_BUS_ADDRESS="${busAddress}"

            exec ${pkgs.s6}/bin/s6-setuidgid ${name} \
              ${cfg.package}/bin/wireplumber
          '';
        }
    )
    runtimeUsers;
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

    # WirePlumber のカスタム設定をシステム全体に配布
    environment.etc."wireplumber/wireplumber.conf.d/99-neet.conf" = lib.mkIf (cfg.settings != {}) {
      source = format.generate "99-neet.conf" cfg.settings;
    };

    system.s6-rc.services = wireplumberServices;
  };
}
