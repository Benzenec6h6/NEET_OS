#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-}"
FLAKE_DIR="${2:-/etc/neet-os}"

if [ "$ACTION" != "switch" ] && [ "$ACTION" != "boot" ] && [ "$ACTION" != "build" ]; then
  echo "usage: neet-rebuild <switch|boot|build> [flake-path]"
  echo "example: neet-rebuild switch /etc/neet-os"
  exit 1
fi

# 1. 新しい toplevel のビルド
echo "==> [neet-rebuild] Building new system from $FLAKE_DIR..."
# flake.nix で公開している packages の toplevel を指定
# (VM環境なら toplevelVm, デスクトップなら toplevelDesktop などを指定可能)
TOPLEVEL=$(nix build "$FLAKE_DIR#packages.x86_64-linux.default" --no-link --print-out-paths)
echo "==> [neet-rebuild] Built toplevel: $TOPLEVEL"

if [ "$ACTION" = "build" ]; then
  exit 0
fi

# 2. プロファイル世代の更新 (/nix/var/nix/profiles/system)
echo "==> [neet-rebuild] Updating system profile..."
nix-env -p /nix/var/nix/profiles/system --set "$TOPLEVEL"

# 3. Limine ブートローダの更新 (boot と switch の両方で実行)
echo "==> [neet-rebuild] Updating Limine bootloader..."
if command -v update-limine >/dev/null 2>&1; then
  update-limine
fi

# 4. switch の場合のみ、稼働中のシステムを動的切り替え
if [ "$ACTION" = "switch" ]; then
  echo "==> [neet-rebuild] Checking if live switch is safe..."

  NEEDS_REBOOT=""

  # (1) カーネルの比較
  if [ -e /run/booted-kernel ] && [ -e "$TOPLEVEL/kernel" ]; then
    CURRENT_KERNEL=$(readlink -f /run/booted-kernel)
    NEW_KERNEL=$(readlink -f "$TOPLEVEL/kernel")
    if [ "$CURRENT_KERNEL" != "$NEW_KERNEL" ]; then
      NEEDS_REBOOT="Kernel has been updated"
    fi
  fi

  # (2) グラフィックスドライバの比較
  if [ -e /run/opengl-driver ] && [ -e "$TOPLEVEL/graphics-drivers" ]; then
    CURRENT_GFX=$(readlink -f /run/opengl-driver)
    NEW_GFX=$(readlink -f "$TOPLEVEL/graphics-drivers")
    if [ "$CURRENT_GFX" != "$NEW_GFX" ]; then
      NEEDS_REBOOT="Graphics driver (Mesa) has been updated"
    fi
  fi

  # 危険な更新がある場合は switch をスキップして安全終了
  if [ -n "$NEEDS_REBOOT" ] && [ "${FORCE:-0}" != "1" ]; then
    echo "--------------------------------------------------"
    echo " [NOTICE] Live switch skipped: $NEEDS_REBOOT"
    echo " Switching live desktop/drivers may cause application crashes."
    echo " Bootloader is already updated. Please reboot your system!"
    echo " (To force switch anyway: FORCE=1 neet-rebuild switch ...)"
    echo "--------------------------------------------------"
    exit 0
  fi

  echo "==> [neet-rebuild] Safe to switch live. Switching running configuration..."

  # (a) /etc, ラッパー, /bin, /run/current-system を更新
  system-init switch "$TOPLEVEL/etc" "$TOPLEVEL/system-path"

  # (b) s6-rc サービスを動的リロード
  if [ -d /run/s6-rc ] && [ -d /etc/s6-rc/compiled ]; then
    echo "==> [neet-rebuild] Updating s6-rc service database..."
    s6-rc-update -l /run/s6-rc /etc/s6-rc/compiled
  fi

  echo "==> [neet-rebuild] Successfully switched to new configuration!"
elif [ "$ACTION" = "boot" ]; then
  echo "==> [neet-rebuild] Boot configuration updated. Will take effect on next reboot."
fi
