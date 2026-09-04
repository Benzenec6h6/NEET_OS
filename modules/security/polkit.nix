{
  pkgs,
  config,
  lib,
  ...
}: {
  # s6-rc サービスデータベース構築用
  system.s6-rc.services.polkitd = {
    type = "longrun";
    dependencies = ["dbus"];
    run = ''
      #!/bin/execlineb -P
      ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
    '';
  };
}
