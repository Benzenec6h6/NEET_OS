{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.loader.limine;
  espSync = config.system.build.espSync;
  limineInstall = config.system.build.limineInstall;
  liminePkg = cfg.package;

  installBootloader = pkgs.writeShellScript "install-limine" ''
    set -euo pipefail

    BOOT_DIR="${cfg.bootDir}"
    LIMINE_PKG="${liminePkg}"
    export LIMINE_TIMEOUT="${toString cfg.timeout}"

    ${lib.optionalString config.boot.secureBoot.enable ''
      export SECUREBOOT_KEY="${toString config.boot.secureBoot.keyPath}"
      export SECUREBOOT_CERT="${toString config.boot.secureBoot.certPath}"
    ''}

    echo "==> [install-limine] 1/2: Synchronizing payloads to ESP..."
    ${espSync}/bin/esp-sync "$BOOT_DIR"

    echo "==> [install-limine] 2/2: Updating Limine binaries, config and NVRAM..."
    exec ${limineInstall}/bin/limine-install "$BOOT_DIR" "$LIMINE_PKG"
  '';
in {
  options = {
    boot.loader.limine = {
      enable = lib.mkEnableOption "Limine bootloader for NEET OS";

      package = lib.mkOption {
        type = lib.types.package;
        default = pkgs.limine;
        description = "Limine package containing UEFI binaries.";
      };

      bootDir = lib.mkOption {
        type = lib.types.str;
        default = "/boot";
        description = "Mount point of the EFI System Partition (ESP).";
      };

      timeout = lib.mkOption {
        type = lib.types.int;
        default = 5;
        description = "Timeout in seconds before booting the default entry.";
      };
    };
  };

  config = lib.mkIf cfg.enable {
    system.build.installBootLoader = installBootloader;

    environment.systemPackages = [
      espSync
      limineInstall
      (pkgs.writeScriptBin "install-bootloader" ''
        #!${pkgs.execline}/bin/execlineb -P
        ${installBootloader}
      '')
    ];
  };
}
