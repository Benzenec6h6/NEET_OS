{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./boot
    ./filesystems
    ./init
    ./networking
    ./security
    ./services/nix-daemon.nix
    ./services/dbus.nix
    ./services/seatd.nix
    ./services/mdevd
    ./services/dhcpcd.nix
    ./services/iwd.nix
    ./system
    ./testing/image.nix
    ./testing/vm-runner.nix
    ./virtualisation/virtio.nix
  ];
}
