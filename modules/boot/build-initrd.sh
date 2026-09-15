#!/bin/sh
set -eu

mkdir -p "$out/bin"

# --- 1. 主役ツールの配置（実体バイナリ） ---
# kmod
cp "@kmod@/bin/kmod" "$out/bin/modprobe"
chmod 755 "$out/bin/modprobe"

# util-linux (switch_root も含む)
for bin in mount umount losetup blkid fdisk fsck switch_root; do
  if [ -f "@utilLinux@/bin/$bin" ]; then
    cp -f "@utilLinux@/bin/$bin" "$out/bin/"
  elif [ -f "@utilLinux@/sbin/$bin" ]; then
    cp -f "@utilLinux@/sbin/$bin" "$out/bin/"
  fi
done

# mdevd & 自作ツール
cp "@mdevd@/bin/mdevd" "$out/bin/mdevd"
cp "@mdevd@/bin/mdevd-coldplug" "$out/bin/mdevd-coldplug"
cp "@earlyInit@/bin/early-init" "$out/bin/early-init"
cp "@mdevdDiskScript@" "$out/bin/mdevd-disk.sh"
chmod 755 "$out/bin/"*

# --- 2. サブツール（BusyBox）の配置 ---
# BusyBox 本体の配置
cp "@busybox@/bin/busybox" "$out/bin/busybox"
chmod 755 "$out/bin/busybox"

# -s -f でリンクを張るが、既存の専用バイナリがある場合は上書きさせない
# （Busybox の --install は既存ファイルがあるとスキップします）
"$out/bin/busybox" --install -s "$out/bin"
