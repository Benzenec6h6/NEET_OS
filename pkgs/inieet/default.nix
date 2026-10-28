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
    ...
  } @ args: let
    cleanArgs = removeAttrs args ["platform"];
  in
    platform.buildRustPackage (cleanArgs
      // {
        inherit pname src;
        version = "0.1.0";
        cargoLock.lockFile = cargoLockFile;
        buildAndTestSubdir = subdir;
      });
in {
  # pkgsStatic を使う例外
  neetMount = mkPackage {
    pname = "neet-mount";
    platform = pkgs.pkgsStatic.rustPlatform;
  };

  neetSecret = mkPackage {
    pname = "neet-secret";
    platform = pkgs.pkgsStatic.rustPlatform;

    nativeBuildInputs = [
      pkgs.buildPackages.pkg-config
    ];

    buildInputs = [
      pkgs.pkgsStatic.tpm2-tss
      pkgs.pkgsStatic.openssl
    ];

    PKG_CONFIG_ALL_STATIC = "1";
  };

  # 通常のパッケージ（1行で書ける）
  neetActivate = mkPackage {pname = "neet-activate";};
  limineInstall = mkPackage {pname = "limine-install";};
  efistubSync = mkPackage {pname = "efistub-sync";};
  espSync = mkPackage {pname = "esp-sync";};
  diskSetup = mkPackage {pname = "disk-setup";};
  neetUki = mkPackage {pname = "neet-uki";};

  # ディレクトリ名とパッケージ名が異なる例外
  bootspecWrite = mkPackage {
    pname = "bootspec-write";
    subdir = "bootspec";
  };
}
