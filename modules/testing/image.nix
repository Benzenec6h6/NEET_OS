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

  # ★サイズを MiB 単位で定義
  espSizeM = 512; # ESP (FAT32): 512 MiB
  rootSizeM = 3584; # Root (Btrfs): 3584 MiB (3.5 GiB)
  # 全体: 先頭1MB + ESP(512MB) + Root(3584MB) + 末尾バックアップGPT用(1MB)
  diskSizeM = 1 + espSizeM + rootSizeM + 1;

  diskImage =
    pkgs.runCommand "neet-os-disk-image" {
      nativeBuildInputs = [
        pkgs.gptfdisk
        pkgs.dosfstools
        pkgs.mtools
        pkgs.btrfs-progs
        pkgs.e2fsprogs
        pkgs.limine
      ];
    } ''
      # 1. ESP (FAT32) イメージの作成
      echo "Creating ESP image..."
      truncate -s ${toString espSizeM}M esp.img
      mkfs.vfat -F 32 -n NEET_BOOT esp.img

      mmd -i esp.img ::/EFI
      mmd -i esp.img ::/EFI/BOOT
      mmd -i esp.img ::/kernels

      mcopy -i esp.img ${pkgs.limine}/share/limine/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI
      mcopy -i esp.img ${toplevel}/kernel ::/kernels/gen-1-vmlinuz
      mcopy -i esp.img ${toplevel}/initrd ::/kernels/gen-1-initrd

      cat <<EOF > limine.conf
      timeout: 5

      /NEET OS (Generation 1 - Current)
          protocol: linux
          kernel_path: boot():/kernels/gen-1-vmlinuz
          module_path: boot():/kernels/gen-1-initrd
          cmdline: init=${toplevel}/init $(cat ${toplevel}/kernel-params)
      EOF
      mcopy -i esp.img limine.conf ::/limine.conf

      # 2. RootFS (Btrfs) イメージの作成
      echo "Creating RootFS image (${rootFsType})..."
      truncate -s ${toString rootSizeM}M rootfs.img

      # ★超重要: -b (バイトサイズ) を指定して、mkfs が勝手にサイズを拡張するのを防ぐ
      ${
        if rootFsType == "btrfs"
        then "mkfs.btrfs -b ${toString (rootSizeM * 1024 * 1024)} -L NEET_OS -r ${rootfs} rootfs.img"
        else if rootFsType == "ext4"
        then "mkfs.ext4 -L NEET_OS -d ${rootfs} rootfs.img ${toString rootSizeM}M"
        else throw "未対応の fsType です"
      }

      # 3. GPT ディスクの構築
      echo "Assembling GPT disk image..."
      truncate -s ${toString diskSizeM}M $out

      # GPT テーブル初期化 & パーティション作成
      sgdisk -Z $out
      # p1: 1MB(2048セクタ) から 512MB
      sgdisk -n 1:2048:+${toString espSizeM}M -t 1:ef00 -c 1:"EFI" $out
      # p2: 513MB から 3584MB
      sgdisk -n 2:${toString ((1 + espSizeM) * 2048)}:+${toString rootSizeM}M -t 2:8300 -c 2:"root" $out

      # 結合 (conv=notrunc)
      dd if=esp.img of=$out bs=1M seek=1 conv=notrunc status=none
      dd if=rootfs.img of=$out bs=1M seek=${toString (1 + espSizeM)} conv=notrunc status=none

      echo "GPT disk image successfully created!"
    '';
in {
  config = lib.mkIf cfg.enable {
    system.build.diskImage = diskImage;
  };
}
