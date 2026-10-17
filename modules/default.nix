{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./boot
    ./disks
    ./filesystems
    ./fonts
    ./hardware
    ./images
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
