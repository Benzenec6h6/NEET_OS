{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./nix-daemon.nix
    ./dbus.nix
    ./seatd.nix
    ./device-manager.nix
    ./gardendevd
    ./mdevd
    ./dhcpcd.nix
    ./iwd.nix
    ./getty.nix
  ];
}
