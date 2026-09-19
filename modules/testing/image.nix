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

  # 1. rootfs の骨格を作成
  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${./populate-rootfs.sh}
    '';

  # 2. 各パーティションサイズ
  espSizeM = 512; # ESP (FAT32) のサイズ (512 MiB)
  rootSizeM = 3584; # Root (Btrfs) のサイズ (3.5 GiB)
  # 全体サイズ: 先頭 1MB (GPTヘッダ) + ESP + Root + 末尾 1MB (GPT予備ヘッダ)
  diskSizeM = 1 + espSizeM + rootSizeM + 1;

  diskImage =
    pkgs.runCommand "neet-os-disk-image" {
      nativeBuildInputs = [
        pkgs.gptfdisk # sgdisk
        pkgs.dosfstools # mkfs.vfat
        pkgs.mtools # mcopy, mmd (マウントなしでFATを操作するツール)
        pkgs.btrfs-progs # mkfs.btrfs
        pkgs.e2fsprogs # mkfs.ext4
        pkgs.limine # BOOTX64.EFI
      ];
    } ''
      # -------------------------------------------------------------
      # A. ESP (FAT32) イメージの生成
      # -------------------------------------------------------------
      echo "Creating ESP image..."
      truncate -s ${toString espSizeM}M esp.img
      mkfs.vfat -F 32 -n NEET_BOOT esp.img

      # ディレクトリ作成
      mmd -i esp.img ::/EFI
      mmd -i esp.img ::/EFI/BOOT
      mmd -i esp.img ::/kernels

      # Limine UEFI バイナリの配置
      mcopy -i esp.img ${pkgs.limine}/share/limine/BOOTX64.EFI ::/EFI/BOOT/BOOTX64.EFI

      # 第1世代のカーネルと initrd を配置
      mcopy -i esp.img ${toplevel}/kernel ::/kernels/gen-1-vmlinuz
      mcopy -i esp.img ${toplevel}/initrd ::/kernels/gen-1-initrd

      # 初期 limine.conf の作成と配置
      cat <<EOF > limine.conf
      timeout: 5

      /NEET OS (Generation 1 - Current)
          protocol: linux
          kernel_path: boot():/kernels/gen-1-vmlinuz
          module_path: boot():/kernels/gen-1-initrd
          cmdline: init=${toplevel}/init $(cat ${toplevel}/kernel-params)
      EOF
      mcopy -i esp.img limine.conf ::/limine.conf

      # -------------------------------------------------------------
      # B. RootFS (Btrfs/ext4) イメージの生成
      # -------------------------------------------------------------
      echo "Creating RootFS image (${rootFsType})..."
      truncate -s ${toString rootSizeM}M rootfs.img
      ${
        if rootFsType == "btrfs"
        then "mkfs.btrfs -L NEET_OS -r ${rootfs} rootfs.img"
        else if rootFsType == "ext4"
        then "mkfs.ext4 -L NEET_OS -d ${rootfs} rootfs.img"
        else throw "未対応の fsType です"
      }

      # -------------------------------------------------------------
      # C. 全体ディスクイメージの組み立て (GPT パーティション)
      # -------------------------------------------------------------
      echo "Assembling final GPT disk image..."
      truncate -s ${toString diskSizeM}M $out

      # 1MB 境界に合わせたセクタ指定 (1 sector = 512 bytes)
      # 1MB = 2048 sectors
      # 512MB = 1048576 sectors
      sgdisk -Z $out
      sgdisk -n 1:2048:+${toString espSizeM}M -t 1:ef00 -c 1:"EFI" $out
      sgdisk -n 2:0:0                        -t 2:8300 -c 2:"root" $out

      # データを所定のオフセットに書き込み (conv=notrunc で上書き)
      # 先頭 1MB (seek=1) に ESP を配置
      dd if=esp.img of=$out bs=1M seek=1 conv=notrunc status=none
      # 1MB + 512MB = 513MB (seek=513) に RootFS を配置
      dd if=rootfs.img of=$out bs=1M seek=${toString (1 + espSizeM)} conv=notrunc status=none

      echo "GPT disk image successfully created!"
    '';
in {
  config = lib.mkIf cfg.enable {
    system.build.diskImage = diskImage;
  };
}
