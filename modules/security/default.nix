{...}: {
  imports = [
    ./ca.nix
    ./pam.nix
    ./polkit.nix
    ./secrets.nix
    ./shadow.nix
    ./tpm2.nix
    ./wrappers.nix
    ./privileges
  ];
}
