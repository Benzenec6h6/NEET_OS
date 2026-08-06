{
  pkgs,
  lib,
}:
pkgs.pkgsStatic.rustPlatform.buildRustPackage {
  pname = "etc-syncer";
  version = "0.1.0";

  # Cargo.toml があるディレクトリ（カレントディレクトリ）を指定
  src = ./.;

  cargoLock = {
    lockFile = ./Cargo.lock;
  };
}
