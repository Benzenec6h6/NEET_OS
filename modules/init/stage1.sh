#!/bin/sh
export PATH=/bin
#/bin/busybox mkdir -p /proc /sys /dev /mnt /tmp /run
mkdir -p /proc /sys /dev /mnt /tmp /run /etc
mount -t proc proc /proc
mount -t sysfs sysfs /sys
mount -t devtmpfs devtmpfs /dev

echo "NEET OS Stage 1: Starting mdevd..."
/bin/mdevd -f /etc/mdev.conf &
MDEVD_PID=$!

echo "NEET OS Stage 1: Loading drivers..."
echo /bin/modprobe > /proc/sys/kernel/modprobe
for mod in @kernelModules@; do
    if command -v modprobe >/dev/null 2>&1; then
        modprobe $mod 2>/dev/null
    else
        find "/lib/modules/@kernelVersion@" -name "$mod.ko*" -exec insmod {} \; 2>/dev/null
    fi
done

echo "NEET OS Stage 1: Triggering coldplug..."
mdevd-coldplug

echo "NEET OS Stage 1: Mounting root filesystems..."
if ! /bin/early-init /mount-plan.json /mnt; then
    echo "FAILED to mount root filesystem! Spawning emergency shell..."
    # 緊急シェルを起動（exit するとパニック）
    exec /bin/sh
fi

echo "NEET OS Stage 1: Preparing Stage 2 env..."
mkdir -p /mnt/bin /mnt/etc /mnt/run /mnt/root /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/var/log
cp /bin/busybox /mnt/bin/busybox
/mnt/bin/busybox --install -s /mnt/bin

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

echo "NEET OS Stage 1: Linking stage2 init..."
ln -sf "@stage2Init@" /mnt/init
echo "NEET OS Stage 1: switch_root!"
kill $MDEVD_PID

exec < "/mnt/dev/@console@" > "/mnt/dev/@console@" 2>&1
exec switch_root /mnt /init
