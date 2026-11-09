{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.images.raw;
  toplevel = config.system.build.toplevel;
  kernel = config.boot.kernelPackages.kernel;

  closure = pkgs.closureInfo {
    rootPaths = [
      toplevel
      kernel
    ];
  };

  # 同一ディレクトリ内のスクリプトを自然に参照
  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${./populate-rootfs.sh}
    '';

  bootloader =
    if (config.boot.loader.efistub.enable or false)
    then "efistub"
    else if (config.boot.loader.limine.enable or false)
    then "limine"
    else throw "boot.loader.limine または boot.loader.efistub のいずれかを有効にしてください";

  espMount = lib.findFirst (mp: config.boot.fileSystems.${mp}.fsType == "vfat") "/boot" (
    builtins.attrNames config.boot.fileSystems
  );

  diskImage =
    pkgs.runCommand "neet-os-disk-image" {
      nativeBuildInputs =
        [
          config.disks.package
          pkgs.gptfdisk
          pkgs.dosfstools
          pkgs.mtools
          pkgs.btrfs-progs
          pkgs.e2fsprogs
          pkgs.util-linux
          pkgs.coreutils
        ]
        ++ lib.optional (bootloader == "limine") pkgs.limine;

      inherit toplevel rootfs bootloader espMount;
      diskPlan = config.system.build.diskPlan;
      diskName = lib.optionalString (cfg.disk != null) cfg.disk;
      diskSizeM = toString cfg.diskSize;
      liminePkg = pkgs.limine;
      uefiShellPkg = "${pkgs.edk2-uefi-shell}/shell.efi";

      ukiFile =
        if (config.boot.uki.enable or false)
        then "${config.system.build.uki}"
        else "";
    } ''
      bash ${./build-disk-image.sh}
    '';
in {
  options.images.raw = {
    enable = lib.mkEnableOption "Raw GPT disk image builder";

    disk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "イメージ化する disks.devices の名前。null なら唯一のディスク";
    };

    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Disk image size in MiB";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.disks.devices != {};
        message = "images.raw: ディスクイメージを作るには disks.devices を定義してください。";
      }
    ];
    system.build.diskImage = diskImage;
  };
}
