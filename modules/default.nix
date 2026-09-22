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
    ./programs/coreutils.nix
    ./security
    ./services
    ./system
    ./testing/image.nix
    ./testing/vm-runner.nix
    ./virtualisation/virtio.nix
  ];
}
