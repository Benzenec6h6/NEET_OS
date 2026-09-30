#!/usr/bin/env bash
set -euo pipefail

# 必須環境変数のチェック
: "${out:?out must be set}"
: "${toplevel:?toplevel must be set}"
: "${rootfs:?rootfs must be set}"
: "${rootFsType:?rootFsType must be set}"
: "${diskSizeM:?diskSizeM must be set}"
: "${espSizeM:?espSizeM must be set}"
: "${rootSizeM:?rootSizeM must be set}"
: "${bootloader:?bootloader must be set}" # "limine" または "efistub"

echo "build-disk-image: starting assemble disk image (${diskSizeM}M)..."

# ==========================================
# 1. ESP (FAT32) イメージの作成
# ==========================================
echo "build-disk-image: creating ESP image (${espSizeM}M)..."
truncate -s "${espSizeM}M" esp.img
mkfs.vfat -F 32 -n NEET_BOOT esp.img

mmd -i esp.img ::/EFI
mmd -i esp.img ::/EFI/BOOT

# ブートローダごとの ESP 構築
if [ "$bootloader" = "limine" ]; then
  : "${liminePkg:?liminePkg must be set for limine}"
  echo "build-disk-image: configuring Limine on ESP..."

  mmd -i esp.img ::/kernels
  mcopy -i esp.img "${liminePkg}/share/limine/BOOTX64.EFI" ::/EFI/BOOT/BOOTX64.EFI
  mcopy -i esp.img "${toplevel}/kernel" ::/kernels/gen-1-vmlinuz
  mcopy -i esp.img "${toplevel}/initrd" ::/kernels/gen-1-initrd

  cat <<EOF > limine.conf
timeout: 5

/NEET OS (Generation 1 - Current)
    protocol: linux
    kernel_path: boot():/kernels/gen-1-vmlinuz
    module_path: boot():/kernels/gen-1-initrd
    cmdline: init=${toplevel}/init $(cat "${toplevel}/kernel-params")
EOF
  mcopy -i esp.img limine.conf ::/limine.conf

elif [ "$bootloader" = "efistub" ]; then

  # ★ UKI がある場合のワンクッション分岐
  if [ -n "${ukiFile:-}" ]; then
    echo "build-disk-image: configuring pure UKI direct boot (No UEFI Shell, No startup.nsh!)..."

    # UKI そのものをデフォルトのブートローダパスに配置するだけ！
    mcopy -i esp.img "${ukiFile}" ::/EFI/BOOT/BOOTX64.EFI

  else
    # 従来の EFISTUB (UEFI Shell による世話焼き)
    : "${uefiShellPkg:?uefiShellPkg must be set}"
    echo "build-disk-image: configuring EFISTUB via UEFI Shell..."

    mmd -i esp.img ::/EFI/NEET
    mcopy -i esp.img "${toplevel}/kernel" ::/EFI/NEET/gen-1-vmlinuz.efi
    mcopy -i esp.img "${toplevel}/initrd" ::/EFI/NEET/gen-1-initrd.img

    mcopy -i esp.img "${uefiShellPkg}" ::/EFI/BOOT/BOOTX64.EFI

    cat <<EOF > startup.nsh
\EFI\NEET\gen-1-vmlinuz.efi initrd=\EFI\NEET\gen-1-initrd.img init=${toplevel}/init $(cat "${toplevel}/kernel-params")
EOF
    mcopy -i esp.img startup.nsh ::/startup.nsh
  fi

else
  echo "build-disk-image: error: unsupported bootloader '$bootloader'" >&2
  exit 1
fi

# ==========================================
# 2. RootFS イメージの作成
# ==========================================
echo "build-disk-image: creating RootFS image (${rootSizeM}M, ${rootFsType})..."
truncate -s "${rootSizeM}M" rootfs.img

case "$rootFsType" in
  btrfs)
    mkfs.btrfs -L NEET_OS -r "$rootfs" rootfs.img
    ;;
  ext4)
    mkfs.ext4 -L NEET_OS -d "$rootfs" rootfs.img
    ;;
  *)
    echo "build-disk-image: error: unsupported fsType '$rootFsType'" >&2
    exit 1
    ;;
esac

# ==========================================
# 3. GPT ディスクの構築と結合
# ==========================================
echo "build-disk-image: assembling GPT partition table..."
truncate -s "${diskSizeM}M" "$out"

sgdisk -Z "$out"
# p1: ESP (1MB から espSizeM まで)
sgdisk -n "1:2048:+${espSizeM}M" -t 1:ef00 -c 1:"EFI" "$out"
# p2: Root (ESP の後ろから rootSizeM 分)
rootStartSector=$(( (1 + espSizeM) * 2048 ))
sgdisk -n "2:${rootStartSector}:+${rootSizeM}M" -t 2:8300 -c 2:"root" "$out"

# 結合
echo "build-disk-image: writing partitions into disk image..."
dd if=esp.img of="$out" bs=1M seek=1 conv=notrunc status=none
dd if=rootfs.img of="$out" bs=1M seek=$(( 1 + espSizeM )) conv=notrunc status=none

echo "build-disk-image: disk image successfully created at $out"
