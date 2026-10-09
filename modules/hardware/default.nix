{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./console.nix
    ./firmware.nix
    ./graphics.nix
    ./i2c.nix
    ./uinput.nix
    ./video/nvidia.nix
    ./video/nvidia-prime.nix
    ./cpu/amd-ucode.nix
    ./cpu/intel-ucode.nix
  ];
}
