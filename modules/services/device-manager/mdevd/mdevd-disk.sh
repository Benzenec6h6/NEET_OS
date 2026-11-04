#!/bin/sh
set -eu

# ★ 改善: Nix 側から注入された安全な static バイナリパスを優先
export PATH="@binPath@:/bin:$PATH"

DEV="$MDEV"
DEVPATH="/dev/$DEV"

if [ ! -b "$DEVPATH" ]; then
  exit 0
fi

if [ "${ACTION:-}" = "remove" ]; then
  find /dev/disk -type l -lname "*/$DEV" -delete 2>/dev/null || true
  exit 0
fi

if [ "${ACTION:-}" = "add" ] || [ "${ACTION:-}" = "change" ]; then
  eval "$(blkid -o export "$DEVPATH" 2>/dev/null || true)"

  make_link() {
    type_dir="$1"
    val="$2"
    if [ -n "$val" ]; then
      mkdir -p "/dev/disk/$type_dir"
      ln -sf "../../$DEV" "/dev/disk/$type_dir/$val"
    fi
  }

  [ -n "${UUID:-}" ] && make_link "by-uuid" "$UUID"
  [ -n "${LABEL:-}" ] && make_link "by-label" "$LABEL"
  [ -n "${PARTUUID:-}" ] && make_link "by-partuuid" "$PARTUUID"
  [ -n "${PARTLABEL:-}" ] && make_link "by-partlabel" "$PARTLABEL"
  [ -n "${ID_FS_TYPE:-}" ] && make_link "by-type" "$ID_FS_TYPE"
fi
