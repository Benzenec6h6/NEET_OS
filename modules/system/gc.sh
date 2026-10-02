#!/usr/bin/env bash
set -euo pipefail

# 使用例:
#   neet-gc +5       # 最新 5 世代を残して他をすべて削除
#   neet-gc 30d      # 30日以上前の世代を削除
#   neet-gc 12 13    # 世代 12, 13 を指定して削除
TARGET_GENS="${1:-+5}"

echo "=================================================="
echo " [neet-gc] Cleaning up old system generations"
echo "=================================================="

# 1. 指定された世代プロファイルの削除
echo "==> [neet-gc] Removing system profile generation(s): $TARGET_GENS..."
nix-env -p /nix/var/nix/profiles/system --delete-generations "$TARGET_GENS"

# 2. Nix Store のゴミ掃除
echo "==> [neet-gc] Collecting garbage from Nix Store..."
nix-store --gc

# 3. ブート環境の同期
# (esp-sync が古い UKI/カーネルを削除し、efistub-sync が古い BootXXXX を削除し、limine は conf を再生成する)
echo "==> [neet-gc] Synchronizing bootloader environment..."
if command -v install-bootloader >/dev/null 2>&1; then
  install-bootloader
else
  echo "==> [neet-gc] warning: 'install-bootloader' not found. Skipping bootloader sync."
fi

echo "=================================================="
echo " [neet-gc] System cleanup completed successfully!"
echo "=================================================="
