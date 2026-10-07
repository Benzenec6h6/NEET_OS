{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.testing.vm;
  toplevel = config.system.build.toplevel;
  kernel = config.boot.kernelPackages.kernel;

  closure = pkgs.closureInfo {
    rootPaths = [
      toplevel
      kernel
    ];
  };

  # 論理的なルート階層（/nix/store, /root など）を作るだけ。どのパーティションに入るかは disk-setup が決める
  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${./populate-rootfs.sh}
    '';

  # 有効になっているブートローダを特定
  bootloader =
    if (config.boot.loader.efistub.enable or false)
    then "efistub"
    else if (config.boot.loader.limine.enable or false)
    then "limine"
    else throw "boot.loader.limine または boot.loader.efistub のいずれかを有効にしてください";

  # ブートローダのファイルを置く先（vfat のマウントポイント）
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

      # UKI が有効ならそのパスを渡し、無効なら空文字
      ukiFile =
        if (config.boot.uki.enable or false)
        then "${config.system.build.uki}"
        else "";
    } ''
      bash ${./build-disk-image.sh}
    '';
in {
  options.testing.vm.disk = lib.mkOption {
    type = lib.types.nullOr lib.types.str;
    default = null;
    description = "イメージ化する disks.devices の名前。null なら唯一のディスク";
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.disks.devices != {};
        message = "testing.vm: ディスクイメージを作るには disks.devices を定義してください。";
      }
    ];
    system.build.diskImage = diskImage;
  };
}
