{...}: {
  imports = [
    ./ca.nix
    ./pam.nix
    ./polkit.nix
    ./secrets.nix
    ./shadow.nix
    ./wrappers.nix
    ./privileges
  ];
}
