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

    if [ ! -d "$BOOT_DIR" ]; then
      echo "limine-install: error: boot directory '$BOOT_DIR' does not exist!" >&2
      exit 1
    fi

    if ! ${pkgs.util-linux}/bin/mountpoint -q "$BOOT_DIR"; then
      echo "limine-install: error: target '$BOOT_DIR' is not a mountpoint!" >&2
      exit 1
    fi

    echo "==> [install-limine] 1/2: Synchronizing payloads to ESP..."
    ${espSync}/bin/esp-sync "$BOOT_DIR"

    echo "==> [install-limine] 2/2: Updating Limine binaries and config..."
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
