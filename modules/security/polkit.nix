{
  pkgs,
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.neet.security.enable {
    # D-Bus のポリシー (system.d) とサービス定義を /etc/dbus-1 に取り込む。
    # これが無いと polkitd は org.freedesktop.PolicyKit1 を所有できず、
    # "Lost the name" で終了して s6 に再起動され続ける。
    services.dbus.packages = [pkgs.polkit.out];
    environment.systemPackages = [pkgs.polkit];

    system.s6-rc.services.polkitd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ lib.optional config.services.syslog.enable "syslog";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
      '';
    };
  };
}
