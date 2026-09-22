#!/bin/sh
set -eu

export PATH=/bin
mkdir -p /proc /sys /dev /mnt /tmp /run /etc
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

# ルートマウントを private に変更する (switch_root や mount --move の EINVAL 防止)
mount --make-rprivate /

echo "NEET OS Stage 1: Starting mdevd..."
/bin/mdevd -f /etc/mdev.conf &
MDEVD_PID=$!

echo "NEET OS Stage 1: Loading drivers..."
echo /bin/modprobe > /proc/sys/kernel/modprobe
for mod in @kernelModules@; do
    if command -v modprobe >/dev/null 2>&1; then
        modprobe $mod 2>/dev/null || true
    else
        find "/lib/modules/@kernelVersion@" -name "$mod.ko*" -exec insmod {} \; 2>/dev/null || true
    fi
done

echo "NEET OS Stage 1: Triggering coldplug..."
mdevd-coldplug

echo "NEET OS Stage 1: Mounting root filesystems..."
if ! /bin/early-init /mount-plan.json /mnt; then
    echo "FAILED to mount root filesystem! Spawning emergency shell..."
    exec /bin/sh
fi

# /mnt が本当にマウントされているかチェック
if ! mountpoint -q /mnt; then
    echo "CRITICAL: /mnt is not a mountpoint after early-init!"
    cat /proc/mounts
    exec /bin/sh
fi

echo "NEET OS Stage 1: Preparing Stage 2 env..."
mkdir -p /mnt/bin /mnt/etc /mnt/run /mnt/root /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/var/log

ln -sf "@systemPath@/bin/sh" /mnt/bin/sh

# プロパゲーションが private になったので、正常に move できる
mount --move /proc /mnt/proc
mount --move /sys /mnt/sys
mount --move /dev /mnt/dev

echo "NEET OS Stage 1: Linking stage2 init..."
ln -sf "@stage2Init@" /mnt/init
echo "NEET OS Stage 1: switch_root!"
kill $MDEVD_PID

exec < "/mnt/dev/@console@" > "/mnt/dev/@console@" 2>&1
exec switch_root /mnt /init
