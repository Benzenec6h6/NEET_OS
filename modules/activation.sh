#!/bin/sh
set -eu  # エラーで停止、未定義変数で停止

# 1. 最優先で /bin を構築する
echo "NEET OS Stage 2: Populating /bin from $SYSTEM_PATH"
mkdir -p /bin
ln -sf "$SYSTEM_PATH/bin"/* /bin/

# PATH を設定（/bin を優先）
export PATH="/bin"

echo "NEET OS Stage 2: Mounting essential filesystems..."
mkdir -p /proc /sys /dev /run /etc /tmp
mountpoint -q /proc || mount -t proc proc /proc
mountpoint -q /sys  || mount -t sysfs sysfs /sys
mountpoint -q /dev  || mount -t devtmpfs devtmpfs /dev

# === [追加] カーネルモジュールと modprobe のセットアップ ===
echo "NEET OS Stage 2: Setting up kernel modules..."
KERNEL_VERSION=$(uname -r)
mkdir -p /lib/modules

# システム全体のモジュールツリーを /lib/modules にリンク
if [ -d "@modulesTree@/lib/modules/$KERNEL_VERSION" ]; then
    ln -sfT "@modulesTree@/lib/modules/$KERNEL_VERSION" "/lib/modules/$KERNEL_VERSION"
fi

# modprobe のパスをカーネルに指定
if [ -e "@kmod@/bin/modprobe" ]; then
    echo "@kmod@/bin/modprobe" > /proc/sys/kernel/modprobe
fi
# ==========================================================

# 2. 各フック（etc-syncer 等）の実行
if [ -n "${HOOK_PATHS:-}" ]; then
    for hook in $HOOK_PATHS; do
        echo "Running hook: $hook"
        "$hook"
    done
fi

# 3. s6 サービスの準備
echo "Preparing s6 service directory..."
rm -rf /run/service
mkdir -p /run/service

if [ -d /etc/s6-scan ]; then
    cp -rL /etc/s6-scan/. /run/service/
    find /run/service -name "run" -exec chmod +x {} +
fi

echo "Activation completed successfully."
