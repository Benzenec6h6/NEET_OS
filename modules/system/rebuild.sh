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

# 3. ブートローダの更新 (boot と switch の両方で実行)
echo "==> [neet-rebuild] Updating bootloader..."
NEW_INSTALLER="$TOPLEVEL/bin/install-bootloader"

# ★ 新しくビルドされた toplevel のインストーラを直接実行
if [ -x "$NEW_INSTALLER" ]; then
  "$NEW_INSTALLER"
else
  echo "==> [neet-rebuild] error: Bootloader installer not found at $NEW_INSTALLER" >&2
  exit 1
fi

# 4. switch の場合のみ、稼働中のシステムを動的切り替え
if [ "$ACTION" = "switch" ]; then
  echo "==> [neet-rebuild] Checking if live switch is safe..."

  CORE="$TOPLEVEL/core"
  NEEDS_REBOOT=""

    if [ ! -e /run/booted-system/neet.json ]; then
      NEEDS_REBOOT="Running system predates core manifest (reboot once to adopt it)"
    elif ! cmp -s /run/booted-system/neet.json "$CORE/neet.json"; then
      NEEDS_REBOOT="Kernel, modules, firmware, kernel params or graphics drivers changed"
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
  neet-activate switch "$CORE"

  if [ -d /run/s6-rc ] && [ -e "$CORE/s6-rc" ]; then
    echo "==> [neet-rebuild] Updating system s6-rc service database..."
    s6-rc-update -l /run/s6-rc "$CORE/s6-rc"
  fi

  # ★ (c) ログイン中の全ユーザーの s6-rc もまとめて動的リロード！
  for USER_DIR in /run/user/*; do
    [ -d "$USER_DIR" ] || continue
    UID_NUM="$(basename "$USER_DIR")"
    
    # UID からユーザー名を取得
    USER_NAME="$(id -nu "$UID_NUM" 2>/dev/null || true)"
    [ -n "$USER_NAME" ] || continue

    USER_LIVE="$USER_DIR/s6-rc"
    USER_NEW_DB="/etc/s6-rc/users/$USER_NAME/compiled"
    USER_NEW_DEFS="/etc/s6-rc/users/$USER_NAME/definitions"

    # セッション（s6-rc）が走っており、新しいDBも存在する場合
    if [ -d "$USER_LIVE" ] && [ -d "$USER_NEW_DB" ]; then
      echo "==> [neet-rebuild] Updating user s6-rc services for $USER_NAME (UID: $UID_NUM)..."

      # restartOnUpdate = false 用の definitions リンクを更新
      if [ -d "$USER_NEW_DEFS" ]; then
        ln -sfn "$USER_NEW_DEFS" "$USER_DIR/service-definitions"
      fi

      # 該当ユーザー権限に降格して安全に s6-rc-update を実行
      s6-setuidgid "$USER_NAME" s6-rc-update -l "$USER_LIVE" "$USER_NEW_DB" || {
        echo "==> [neet-rebuild] Warning: Failed to update user s6-rc for $USER_NAME" >&2
      }
    fi
  done

  echo "==> [neet-rebuild] Successfully switched to new configuration!"
elif [ "$ACTION" = "boot" ]; then
  echo "==> [neet-rebuild] Boot configuration updated. Will take effect on next reboot."
fi
