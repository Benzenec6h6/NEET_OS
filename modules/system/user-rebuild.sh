#!/usr/bin/env bash
set -euo pipefail

ACTION="${1:-switch}"
USER_NAME="$(id -un)"
USER_UID="$(id -u)"
XDG_RUNTIME_DIR="/run/user/$USER_UID"
LIVE_DIR="$XDG_RUNTIME_DIR/s6-rc"
NEW_DB="/etc/s6-rc/users/$USER_NAME/compiled"
NEW_DEFS="/etc/s6-rc/users/$USER_NAME/definitions"

echo "==> [neet-user-rebuild] Updating user session services for $USER_NAME..."

if [ ! -d "$LIVE_DIR" ]; then
  echo "==> [neet-user-rebuild] Error: User s6-rc live directory ($LIVE_DIR) not found. Are you in an active session?" >&2
  exit 1
fi

if [ ! -d "$NEW_DB" ]; then
  echo "==> [neet-user-rebuild] Error: Compiled DB ($NEW_DB) not found. Did you define system.s6-rc.users.$USER_NAME.services?" >&2
  exit 1
fi

# 1. restartOnUpdate = false 用の実体定義リンクを最新世代に向ける
if [ -d "$NEW_DEFS" ]; then
  ln -sfn "$NEW_DEFS" "$XDG_RUNTIME_DIR/service-definitions"
fi

# 2. s6-rc-update を実行！
# (restartOnUpdate = false の Sway 等は一切 kill されず、変更のあった fcitx5 等だけがリロードされる)
s6-rc-update -l "$LIVE_DIR" "$NEW_DB"

echo "==> [neet-user-rebuild] Successfully switched user services!"
