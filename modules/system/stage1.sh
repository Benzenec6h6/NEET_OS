#!/bin/sh
export PATH=/bin
# 1. 最小限の道具を Stage 1 に展開
/bin/busybox mkdir -p /proc /sys /dev /mnt /tmp /run
/bin/busybox --install -s /bin

# 2. 仮想ファイルシステムのマウント
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# 3. ドライバのロード (Built-inの場合は空振りするだけなので安全)
echo "NEET OS Stage 1: Loading drivers..."
echo /bin/modprobe > /proc/sys/kernel/modprobe
for mod in virtio virtio_ring virtio_pci 9pnet 9pnet_virtio 9p; do
  modprobe $mod 2>/dev/null || find /lib/modules/@kernelVersion@ -name "$mod.ko*" -exec insmod {} \; 2>/dev/null
done

# 4. 9pストアのマウント
echo "NEET OS Stage 1: Mounting 9p store..."
mount -t tmpfs tmpfs /mnt
mkdir -p /mnt/nix/store
if ! mount -t 9p -o trans=virtio,version=9p2000.L,msize=1048576 nixstore /mnt/nix/store; then
  echo "FAILED to mount 9p store."
  exec /bin/sh
fi

echo "NEET OS Stage 1: Preparing Stage 2 env..."

# 5. Stage 2 (新しいルート) の基本ディレクトリ作成
mkdir -p /mnt/bin /mnt/etc /mnt/run /mnt/root /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/var/log

# 6. 【救命ボート】Stage 1 の「静的」BusyBox を Stage 2 に物理コピー
# これにより、Stage 2 の /bin/sh はライブラリなしで確実に動けるようになる
cp /bin/busybox /mnt/bin/busybox
/mnt/bin/busybox --install -s /mnt/bin

# 7. システムパッケージを /bin へ展開
# ホスト側のパス (@systemPath@) は Stage 1 では /mnt の下にあります
for f in "/mnt@systemPath@/bin/"*; do
  [ -e "$f" ] || continue
  name=$(basename "$f")
  # すでに busybox で作ったリンクは上書きせず、無いものだけをリンク
  if [ ! -e "/mnt/bin/$name" ]; then
    ln -s "@systemPath@/bin/$name" "/mnt/bin/$name"
  fi
done

echo "NEET OS Stage 1: switch_root!"
# デバッグ用：置換されたパスが空でないか確認
echo "Debug: NEW_INIT is [@stage2Init@]"

# 8. switch_root 実行
# ダブルクォートで囲むことで、引数の欠落を防ぎます
exec switch_root "/mnt" "@stage2Init@"
