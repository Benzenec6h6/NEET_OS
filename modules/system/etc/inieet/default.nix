{
  pkgs,
  lib,
}: let
  src = lib.cleanSource ./.;
  cargoLockFile = ./Cargo.lock;
in {
  earlyInit = pkgs.pkgsStatic.rustPlatform.buildRustPackage {
    pname = "early-init";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "early-init";
  };
  systemInit = pkgs.rustPlatform.buildRustPackage {
    pname = "system-init";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "system-init";
  };
  limineInstall = pkgs.rustPlatform.buildRustPackage {
    pname = "limine-install";
    version = "0.1.0";
    inherit src;
    cargoLock.lockFile = cargoLockFile;
    buildAndTestSubdir = "limine-install";
  };
}
