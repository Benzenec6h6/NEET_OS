{
  pkgs,
  lib,
}: let
  src = lib.cleanSource ./.;
  cargoLockFile = ./Cargo.lock;

  # 共通のビルド関数（subdir が省略されたら pname と同じにする）
  mkPackage = {
    pname,
    subdir ? pname,
    platform ? pkgs.rustPlatform,
  }:
    platform.buildRustPackage {
      inherit pname src;
      version = "0.1.0";
      cargoLock.lockFile = cargoLockFile;
      buildAndTestSubdir = subdir;
    };
in {
  # pkgsStatic を使う例外
  neetMount = mkPackage {
    pname = "neet-mount";
    platform = pkgs.pkgsStatic.rustPlatform;
  };

  # 通常のパッケージ（1行で書ける）
  neetActivate = mkPackage {pname = "neet-activate";};
  neetSecret = mkPackage {pname = "neet-secret";};
  limineInstall = mkPackage {pname = "limine-install";};
  efistubSync = mkPackage {pname = "efistub-sync";};
  espSync = mkPackage {pname = "esp-sync";};
  diskSetup = mkPackage {pname = "disk-setup";};

  # ディレクトリ名とパッケージ名が異なる例外
  bootspecWrite = mkPackage {
    pname = "bootspec-write";
    subdir = "bootspec";
  };
}
