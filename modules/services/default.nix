{...}: {
  imports = [
    ./nix-daemon.nix
    ./bluez.nix
    ./chrony.nix
    ./dbus.nix
    ./seatd.nix
    ./device-manager
    ./display-manager
    ./dhcpcd.nix
    ./fcron.nix
    ./flatpak.nix
    ./fstrim.nix
    ./fwupd.nix
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
    ./upower.nix
  ];
}
