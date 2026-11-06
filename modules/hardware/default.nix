{...}: {
  imports = [
    ./firmware.nix
    ./graphics.nix
    ./i2c.nix
    ./keyboard.nix
    ./uinput.nix
    ./video/nvidia.nix
    ./video/nvidia-prime.nix
    ./cpu/microcode.nix
  ];
}
