{...}: {
  imports = [
    ./qemu
    ./docker.nix
    ./kvm.nix
    ./virtio.nix
  ];
}
