{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.testing.vm;
  rootFsType = config.boot.fileSystems."/".fsType;
  toplevel = config.system.build.toplevel;
  kernel = config.boot.kernelPackages.kernel;

  closure = pkgs.closureInfo {
    rootPaths = [
      toplevel
      kernel
    ];
  };

  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${./populate-rootfs.sh}
    '';

  diskSizeM = cfg.diskSize;
  espSizeM = 512;
  rootSizeM = diskSizeM - espSizeM - 2;

  # 有効になっているブートローダを特定
  bootloader =
    if (config.boot.loader.efistub.enable or false)
    then "efistub"
    else if (config.boot.loader.limine.enable or false)
    then "limine"
    else throw "boot.loader.limine または boot.loader.efistub のいずれかを有効にしてください";

  diskImage =
    pkgs.runCommand "neet-os-disk-image" {
      nativeBuildInputs =
        [
          pkgs.gptfdisk
          pkgs.dosfstools
          pkgs.mtools
          pkgs.btrfs-progs
          pkgs.e2fsprogs
        ]
        ++ lib.optional (bootloader == "limine") pkgs.limine;

      inherit toplevel rootfs rootFsType diskSizeM espSizeM rootSizeM bootloader;
      liminePkg = pkgs.limine;
    } ''
      bash ${./build-disk-image.sh}
    '';
in {
  config = lib.mkIf cfg.enable {
    system.build.diskImage = diskImage;
  };
}
