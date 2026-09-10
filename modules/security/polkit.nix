{
  pkgs,
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.neet.security.enable {
    system.s6-rc.services.polkitd = {
      type = "longrun";
      dependencies = ["dbus"];
      run = ''
        #!/bin/execlineb -P
        ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
      '';
    };
  };
}
