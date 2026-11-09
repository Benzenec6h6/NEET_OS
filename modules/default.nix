{...}: {
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
    ./virtualisation/docker.nix
    ./virtualisation/kvm.nix
    ./virtualisation/virtio.nix
    ./xdg
  ];
}
