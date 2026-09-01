#!/bin/sh
export PATH=/bin

# 1. 最小限の道具を Stage 1 に展開
/bin/busybox mkdir -p /proc /sys /dev /mnt /tmp /run
/bin/busybox --install -s /bin

# 2. 仮想ファイルシステムのマウント
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# 3. ドライバのロード 
echo "NEET OS Stage 1: Loading drivers..."
echo /bin/modprobe > /proc/sys/kernel/modprobe

# kmod/modprobe があれば使い、無ければ find + insmod でフォールバック
for mod in @kernelModules@; do
    if command -v modprobe >/dev/null 2>&1; then
        modprobe $mod 2>/dev/null
    else
        find "/lib/modules/@kernelVersion@" -name "$mod.ko*" -exec insmod {} \; 2>/dev/null
    fi
done

# 4. 動的マウント処理 (Nix側で生成されたマウントコマンドの展開)
echo "NEET OS Stage 1: Mounting root filesystems..."
mkdir -p /mnt
mkdir -p /mnt/nix/store

@mountCommands@

echo "NEET OS Stage 1: Preparing Stage 2 env..."

# 5. Stage 2 (新しいルート) の基本ディレクトリ作成
mkdir -p /mnt/bin /mnt/etc /mnt/run /mnt/root /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/var/log

# 6. 【救命ボート】Stage 1 の「静的」BusyBox を Stage 2 に物理コピー
cp /bin/busybox /mnt/bin/busybox
/mnt/bin/busybox --install -s /mnt/bin

# 7. システムパッケージを /bin へ展開
for f in "/mnt@systemPath@/bin/"*; do
    [ -e "$f" ] || continue
    name=$(basename "$f")
    if [ ! -e "/mnt/bin/$name" ]; then
        ln -s "@systemPath@/bin/$name" "/mnt/bin/$name"
    fi
done

mount --move /proc /mnt/proc
mount --move /sys /mnt/sys
mount --move /dev /mnt/dev

echo "NEET OS Stage 1: switch_root!"
echo "Debug: NEW_INIT is [@stage2Init@]"

# 8. switch_root 実行
echo "NEET OS Stage 1: Creating skeleton directories in new root..."
# 仮想ファイルシステムと基本ディレクトリの枠組みを作成
mkdir -p /mnt/dev /mnt/proc /mnt/sys /mnt/run /mnt/etc /mnt/bin

echo "NEET OS Stage 1: Linking stage2 init..."
ln -sf "@stage2Init@" /mnt/init

echo "NEET OS Stage 1: switch_root!"
#exec switch_root /mnt /init
exec switch_root -c /dev/ttyS0 /mnt /init
