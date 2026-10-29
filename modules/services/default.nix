{...}: {
  imports = [
    ./nix-daemon.nix
    ./dbus.nix
    ./seatd.nix
    ./device-manager.nix
    ./display-manager
    ./gardendevd
    ./mdevd
    ./dhcpcd.nix
    ./iwd.nix
    ./getty.nix
    ./sessiond
    ./sessiond-uaccess
    ./nvidia-powerd
    ./pipewire.nix
    ./rtkit.nix
    ./openssh.nix
    ./sshguard.nix
    ./syslog.nix
  ];
}
