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
    ./services
    ./system
    ./testing/image.nix
    ./testing/vm-runner.nix
    ./virtualisation/virtio.nix
  ];
}
