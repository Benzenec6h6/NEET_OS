{config, ...}: let
  kernel = config.boot.kernelPackages.kernel;
in {
  imports = [
    ./console.nix
    ./kernel.nix
    ./initrd.nix
    ./sysctl.nix
    ./limine.nix
    ./secureboot.nix
    ./efistub.nix
    ./uki.nix
  ];

  config = {
    system.build.kernel = kernel;
  };
}
