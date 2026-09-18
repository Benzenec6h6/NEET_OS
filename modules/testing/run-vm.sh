#!/bin/sh
set -eu

QEMU_ARGS=(
  -kernel "@kernel@/bzImage"
  -initrd "@initrd@/initrd"
  -append "@cmdline@ root=/dev/vda"
  -m "@memorySize@"
  -smp "@cores@"
  -cpu host -enable-kvm
  -no-reboot
  -device virtio-rng-pci
  -device intel-hda
  -device hda-duplex
  -serial mon:stdio
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0
  -drive "file=@diskImage@,if=virtio,format=raw@snapshotFlag@"
)

# グラフィック設定の条件分岐
if [ "@enableGraphics@" = "1" ]; then
  QEMU_ARGS+=(
    -display gtk
    -vga none
    -device virtio-gpu-pci
    -device virtio-keyboard-pci
    -device virtio-tablet-pci
  )
else
  QEMU_ARGS+=(-nographic)
fi

# 9pストア共有の設定
if [ "@enableSharedStore@" = "1" ]; then
  QEMU_ARGS+=(
    -fsdev local,security_model=none,id=fsdev-store,path=/nix/store,readonly=on
    -device virtio-9p-pci,fsdev=fsdev-store,mount_tag=nixstore
  )
fi

if [ "@enableSharedConfig@" = "1" ]; then
  # sourcePath が空文字の場合は、スクリプト実行時のカレントディレクトリ $(pwd) を使用する
  HOST_SRC="@sourcePath@"
  if [ -z "$HOST_SRC" ]; then
    HOST_SRC="$(pwd)"
  fi

  echo "run-vm: mounting host directory '$HOST_SRC' to /etc/neet-os"

  QEMU_ARGS+=(
    -fsdev local,security_model=none,id=fsdev-config,path="$HOST_SRC"
    -device virtio-9p-pci,fsdev=fsdev-config,mount_tag=neet_os_src
  )
fi

exec "@qemuBinary@" "${QEMU_ARGS[@]}" "$@"
