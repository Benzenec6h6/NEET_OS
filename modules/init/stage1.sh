#!/bin/sh
set -eu

export PATH=/bin

# 失敗したら理由を表示してレスキューシェルに入る（PID 1 を死なせない）
die() {
    echo "NEET OS Stage 1: FATAL: $*"
    exec /bin/sh
}

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
        # 失敗を握りつぶさず表示する（モジュール名の誤りに気づけるように）
        modprobe $mod || echo "NEET OS Stage 1: warning: modprobe $mod failed"
    else
        find "/lib/modules/@kernelVersion@" -name "$mod.ko*" -exec insmod {} \; 2>/dev/null || true
    fi
done

echo "NEET OS Stage 1: Triggering coldplug..."
mdevd-coldplug

echo "NEET OS Stage 1: Mounting root filesystems..."
/bin/early-init /mount-plan.json /mnt || die "early-init failed to mount filesystems"

# /mnt が本当にマウントされているかチェック
if ! mountpoint -q /mnt; then
    cat /proc/mounts
    die "/mnt is not a mountpoint after early-init"
fi

echo "NEET OS Stage 1: Preparing Stage 2 env..."
mkdir -p /mnt/bin /mnt/etc /mnt/run /mnt/root /mnt/proc /mnt/sys /mnt/dev /mnt/tmp /mnt/var/log \
    || die "failed to prepare /mnt (read-only root?)"

ln -sf "@systemPath@/bin/sh" /mnt/bin/sh || die "failed to link /mnt/bin/sh"

# プロパゲーションが private になったので、正常に move できる
mount --move /proc /mnt/proc || die "failed to move /proc"
mount --move /sys /mnt/sys || die "failed to move /sys"
mount --move /dev /mnt/dev || die "failed to move /dev"

TARGET_INIT="@stage2Init@"

if [ -f /proc/cmdline ]; then
    for param in $(cat /proc/cmdline); do
        case "$param" in
            init=*)
                TARGET_INIT="${param#init=}"
                echo "NEET OS Stage 1: Overriding init with $TARGET_INIT"
                ;;
        esac
    done
fi

echo "NEET OS Stage 1: Linking stage2 init..."
ln -sf "@stage2Init@" /mnt/init || die "failed to link /mnt/init"
echo "NEET OS Stage 1: switch_root!"
kill $MDEVD_PID

exec < "/mnt/dev/@console@" > "/mnt/dev/@console@" 2>&1
exec switch_root /mnt /init
