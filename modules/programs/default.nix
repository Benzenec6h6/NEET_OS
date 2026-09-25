{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./coreutils.nix
    ./sh.nix
    ./bash.nix
  ];
}
