{...}: {
  imports = [
    ./ca.nix
    ./pam.nix
    ./polkit.nix
    ./shadow.nix
    ./wrappers.nix
    ./privileges
  ];
}
