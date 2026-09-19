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

  # ★ VM 設定の diskSize (8192 MiB) から各サイズを動的に計算
  diskSizeM = cfg.diskSize;
  espSizeM = 512;
  # 全体から [先頭GPT 1MB] + [ESP 512MB] + [末尾GPT 1MB] を引いた残りを Root に割り当てる
  rootSizeM = diskSizeM - espSizeM - 2;

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
      echo "Creating ESP image (${toString espSizeM}M)..."
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
      # 7.5GB ほどの十分な空き枠を取ってから流し込むので、mkfs がサイズを拡大することはない
      echo "Creating RootFS image (${toString rootSizeM}M)..."
      truncate -s ${toString rootSizeM}M rootfs.img

      ${
        if rootFsType == "btrfs"
        then "mkfs.btrfs -L NEET_OS -r ${rootfs} rootfs.img"
        else if rootFsType == "ext4"
        then "mkfs.ext4 -L NEET_OS -d ${rootfs} rootfs.img"
        else throw "未対応の fsType です"
      }

      # 3. GPT ディスクの構築
      echo "Assembling GPT disk image (${toString diskSizeM}M)..."
      truncate -s ${toString diskSizeM}M $out

      sgdisk -Z $out
      # p1: ESP (1MB から 512MB)
      sgdisk -n 1:2048:+${toString espSizeM}M -t 1:ef00 -c 1:"EFI" $out
      # p2: Root (513MB から 残りすべて)
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
