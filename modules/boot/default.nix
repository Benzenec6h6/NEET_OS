{config, ...}: let
  kernel = config.boot.kernelPackages.kernel;
in {
  imports = [
    ./console.nix
    ./kernel.nix
    ./initrd.nix
    ./modprobe.nix
    ./sysctl.nix
    ./bootloader
  ];

  config = {
    system.build.kernel = kernel;
  };
}
