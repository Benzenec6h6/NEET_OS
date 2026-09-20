{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./nix-daemon.nix
    ./dbus.nix
    ./seatd.nix
    ./mdevd
    ./dhcpcd.nix
    ./iwd.nix
    ./getty.nix
  ];
}
