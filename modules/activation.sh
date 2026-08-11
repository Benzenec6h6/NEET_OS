#!/bin/sh
set -eu  # エラーで停止、未定義変数で停止

# 1. 最優先で /bin を構築する
# これがないと、以降の #!/bin/sh や #!/bin/execlineb が全滅します
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
  # -L でシンボリックリンクを辿って実体をコピー
  cp -rL /etc/s6-scan/. /run/service/
  # run スクリプトに実行権限を付与
  find /run/service -name "run" -exec chmod +x {} +
fi

echo "Activation completed successfully."
