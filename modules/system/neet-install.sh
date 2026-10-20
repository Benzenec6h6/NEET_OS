#!/usr/bin/env bash
set -euo pipefail

# 使い方: neet-install --flake .#my-desktop --device /dev/nvme0n1
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
# Flake から self-contained なディスク操作ツールを取り出す
DISK_TOOL=$(nix build "${FLAKE}.system.build.diskTool" --no-link --print-out-paths)/bin/neet-disk

echo "==> [2/4] ディスクを初期化してマウント中 (${DEVICE} -> ${MOUNT_POINT})..."
# plan.json のパスを渡す必要すらなく、引数を渡すだけで動く
"$DISK_TOOL" format --device "$DEVICE" --yes
"$DISK_TOOL" mount "$MOUNT_POINT" --device "$DEVICE"

cleanup() {
  echo "==> アンマウント処理中..."
  umount -R "$MOUNT_POINT" || true
}
trap cleanup EXIT

echo "==> [3/4] システム本体 (toplevel) をビルドして転送中..."
# neet.json を含む完全なシステムツリーが /mnt/nix/store に書き込まれる
TOPLEVEL=$(nix build "${FLAKE}.system.build.toplevel" --store "$MOUNT_POINT" --print-out-paths)

# ターゲットの世代リンクを張る
mkdir -p "${MOUNT_POINT}/run"
ln -sfn "$TOPLEVEL" "${MOUNT_POINT}/run/current-system"

echo "==> [4/4] ブートローダ (Limine / ESP) をセットアップ中..."
# Limine と ESP 同期を実行
limine-install "$DEVICE"
esp-sync --esp "${MOUNT_POINT}/boot" --toplevel "$TOPLEVEL"

echo "========================================"
echo " NEET_OS のインストールが成功しました！"
echo " 再起動 (reboot) してください。"
echo "========================================"
