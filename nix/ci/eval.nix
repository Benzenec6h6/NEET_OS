{
  pkgs,
  lib,
  neetModules,
}:
lib.evalModules {
  specialArgs = {inherit pkgs lib;};
  modules = [
    neetModules
    {
      boot.fileSystems."/".fsType = "btrfs";
      boot.fileSystems."/".device = "/dev/dummy";
      boot.loader.limine.enable = true;
      testing.vm.enable = true;

      disks.devices.main.partitions = [
        {
          name = "esp";
          size = "512M";
          content = {
            type = "vfat";
            mountPoint = "/boot";
          };
        }
        {
          name = "root";
          content = {
            type = "btrfs";
            mountPoint = "/";
          };
        }
      ];
    }
  ];
}
