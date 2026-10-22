#!/usr/bin/env bash
set -euo pipefail

FLAKE=""
DEVICE=""
MOUNT_POINT="/mnt"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --flake) FLAKE="$2"; shift 2 ;;
    --device) DEVICE="$2"; shift 2 ;;
    --mount-point) MOUNT_POINT="$2"; shift 2 ;;
    *) echo "Unknown option: $1"; exit 1 ;;
  esac
done

if [[ -z "$FLAKE" || -z "$DEVICE" ]]; then
  echo "usage: neet-install --flake <uri#host> --device </dev/sdX|/dev/nvmeXn1>"
  exit 1
fi

echo "==> [1/4] ディスクツール (neet-disk) を準備中..."
DISK_TOOL=$(nix build "${FLAKE}.system.build.diskTool" --no-link --print-out-paths)/bin/neet-disk

echo "==> [2/4] ディスクを初期化してマウント中 (${DEVICE} -> ${MOUNT_POINT})..."
"$DISK_TOOL" format --device "$DEVICE" --yes
"$DISK_TOOL" mount "$MOUNT_POINT" --device "$DEVICE"

cleanup() {
  echo "==> アンマウント処理中..."
  umount -R "$MOUNT_POINT" || true
}
trap cleanup EXIT

echo "==> [3/4] システム本体 (toplevel) をビルドして転送中..."
TOPLEVEL=$(nix build "${FLAKE}.system.build.toplevel" --store "$MOUNT_POINT" --print-out-paths)

# ★重要: 第1世代としてのプロファイルリンクをターゲット側に作成する
# これがないと esp-sync が「世代が存在しない」と判断してスキップしてしまう
mkdir -p "${MOUNT_POINT}/nix/var/nix/profiles"
ln -sfn "$TOPLEVEL" "${MOUNT_POINT}/nix/var/nix/profiles/system-1-link"
ln -sfn "system-1-link" "${MOUNT_POINT}/nix/var/nix/profiles/system"

# /run/current-system も張る
mkdir -p "${MOUNT_POINT}/run"
ln -sfn "$TOPLEVEL" "${MOUNT_POINT}/run/current-system"

echo "==> [4/4] ブートローダをセットアップ中..."
# ★ユーザーが efistub / limine のどちらを選んでいても、設定された側のスクリプトがビルドされる
INSTALL_BOOTLOADER=$(nix build "${FLAKE}.system.build.installBootLoader" --store "$MOUNT_POINT" --no-link --print-out-paths)

# chroot してターゲットの環境下で installBootLoader を実行
# （esp-sync がターゲットの /boot と /nix/var/nix/profiles を正しく見られるようにするため）
# 必要に応じて /dev, /proc, /sys をバインドマウントするか、chroot / unshare で実行
chroot "$MOUNT_POINT" "$INSTALL_BOOTLOADER"

echo "========================================"
echo " NEET_OS のインストールが成功しました！"
echo " 再起動 (reboot) してください。"
echo "========================================"
