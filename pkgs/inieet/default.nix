{
  pkgs,
  lib,
}: let
  src = lib.cleanSource ./.;
  cargoLockFile = ./Cargo.lock;
in {
  neetMount = pkgs.pkgsStatic.rustPlatform.buildRustPackage {
    pname = "neet-mount";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "neet-mount";
  };
  neetActivate = pkgs.rustPlatform.buildRustPackage {
    pname = "neet-activate";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "neet-activate";
  };
  limineInstall = pkgs.rustPlatform.buildRustPackage {
    pname = "limine-install";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "limine-install";
  };
  efistubSync = pkgs.rustPlatform.buildRustPackage {
    pname = "efistub-sync";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "efistub-sync";
  };
  espSync = pkgs.rustPlatform.buildRustPackage {
    pname = "esp-sync";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "esp-sync";
  };
  bootspecWrite = pkgs.rustPlatform.buildRustPackage {
    pname = "bootspec-write";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "bootspec";
  };
  diskSetup = pkgs.rustPlatform.buildRustPackage {
    pname = "disk-setup";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "disk-setup";
  };
}
