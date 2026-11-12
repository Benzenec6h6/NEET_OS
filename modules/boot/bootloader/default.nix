{
  config,
  lib,
  ...
}: {
  imports = [
    ./efistub.nix
    ./limine.nix
    ./secureboot.nix
    ./uki.nix
  ];

  options.boot.loader.generationLimit = lib.mkOption {
    type = lib.types.nullOr lib.types.ints.positive;
    default = 5;
    description = ''
      Maximum number of recent generations to keep on the EFI System Partition (ESP)
      and in bootloader entries. Older generations are skipped and removed from the ESP.
      Set to null for unlimited.
    '';
  };

  config = {
    assertions = [
      {
        assertion = !(config.boot.loader.limine.enable && config.boot.loader.efistub.enable);
        message = "boot.loader.limine and boot.loader.efistub cannot be enabled at the same time.";
      }
    ];
  };
}
