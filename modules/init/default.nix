{
  config,
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./stage1.nix
    ./stage2.nix
    ./s6-rc
  ];
}
