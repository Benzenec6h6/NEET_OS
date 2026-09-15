{
  config,
  lib,
  ...
}: {
  imports = [
    ../../modules/testing/image.nix
    ../../modules/testing/vm-runner.nix
    ../../configuration.nix
  ];

  # VM用の設定
  virtualisation.virtio.enable = true;

  boot.fileSystems."/" = {
    device = "LABEL=NEET_OS";
    fsType = "btrfs";
    options = ["compress=zstd"];
    neededForBoot = true;
  };

  # VMランナーを有効化
  testing.vm.enable = true;
  testing.vm.graphics = true;

  services.seatd = {
    enable = true;
    group = "seat";
    debug = true;
  };

  networking = {
    upInterfaces = ["lo" "eth0"];
    dhcpInterfaces = ["eth0"];
  };
}
