{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./boot
    ./disks
    ./filesystems
    ./hardware
    ./init
    ./networking
    ./programs
    ./security
    ./services
    ./system
    ./testing/image.nix
    ./testing/vm-runner.nix
    ./virtualisation/virtio.nix
    ./xdg
  ];
}
