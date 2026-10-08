#!/usr/bin/env bash
set -eu

if [ "@isPersistent@" = "1" ]; then
  # ==========================================
  # 永続化モード (persistent = true)
  # ==========================================
  STATE_DIR="$(pwd)/.vm-state"
  mkdir -p "$STATE_DIR"

  VARS_FILE="$STATE_DIR/OVMF_VARS.fd"
  OVERLAY_DISK="$STATE_DIR/disk.qcow2"

  # NVRAM が無ければ初回のみコピー
  if [ ! -f "$VARS_FILE" ]; then
    cp "@ovmfVars@" "$VARS_FILE"
    chmod 600 "$VARS_FILE"
  fi

  # 差分オーバーレイディスクが無ければ初回のみ作成
  # （Nix Store 内のディスクイメージを backing file として参照）
  if [ ! -f "$OVERLAY_DISK" ]; then
    echo "run-vm: creating persistent qcow2 overlay at $OVERLAY_DISK..."
    "@qemuImgBinary@" create -f qcow2 -b "@diskImage@" -F raw "$OVERLAY_DISK"
  else
    echo "run-vm: reusing persistent overlay at $OVERLAY_DISK"
  fi

  DRIVE_ARG="file=$OVERLAY_DISK,if=virtio,format=qcow2"
else
  # ==========================================
  # 使い捨てモード (persistent = false)
  # ==========================================
  TMPDIR="$(mktemp -d)"
  trap 'rm -rf "$TMPDIR"' EXIT

  VARS_FILE="$TMPDIR/OVMF_VARS.fd"
  cp "@ovmfVars@" "$VARS_FILE"
  chmod 600 "$VARS_FILE"

  DRIVE_ARG="file=@diskImage@,if=virtio,format=raw,snapshot=on"
fi

QEMU_ARGS=(
  # UEFI ファームウェア
  -drive "if=pflash,format=raw,unit=0,readonly=on,file=@ovmfCode@"
  -drive "if=pflash,format=raw,unit=1,file=$VARS_FILE"

  -m "@memorySize@"
  -smp "@cores@"
  -cpu host -enable-kvm
  -device virtio-rng-pci
  -device intel-hda
  -device hda-duplex
  -serial mon:stdio
  -netdev user,id=net0
  -device virtio-net-pci,netdev=net0

  # ★ 作成したドライブ引数を使用
  -drive "$DRIVE_ARG"
)

# グラフィック設定
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

# 9pストア共有
if [ "@enableSharedStore@" = "1" ]; then
  QEMU_ARGS+=(
    -fsdev local,security_model=none,id=fsdev-store,path=/nix/store,readonly=on
    -device virtio-9p-pci,fsdev=fsdev-store,mount_tag=nixstore
  )
fi

# 9p設定ディレクトリ共有
if [ "@enableSharedConfig@" = "1" ]; then
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
