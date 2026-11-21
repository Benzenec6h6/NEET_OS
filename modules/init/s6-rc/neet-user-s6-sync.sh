#!/usr/bin/env bash
# usage: neet-user-s6-sync <sync|update>
#   sync   : 現行世代のDBを用意してパスを標準出力へ
#   update : sync + 稼働中liveへ s6-rc-update + 古い世代のGC
set -euo pipefail

mode="${1:-sync}"
user="$(id -un)"
: "${XDG_RUNTIME_DIR:=/run/user/$(id -u)}"

src="$(readlink -f "/etc/s6-rc/users/$user/compiled")"
[ -d "$src" ] || { echo "no user db for $user" >&2; exit 1; }

root="$XDG_RUNTIME_DIR/s6-rc-db"
live="${S6_LIVE_DIR:-$XDG_RUNTIME_DIR/s6-rc}"
gen="$root/$(basename "$src")"     # storeのハッシュ付き名 = 世代名(不変)

umask 077
mkdir -p "$root"

if [ ! -d "$gen" ]; then
  tmp="$(mktemp -d "$root/.tmp.XXXXXX")"
  cp -r --no-preserve=mode,ownership "$src/." "$tmp/"
  chmod -R u+w "$tmp"
  mv -T "$tmp" "$gen" || { rm -rf "$tmp"; [ -d "$gen" ]; }  # 競合時は相手の勝ち
fi
ln -sfn "$gen" "$root/.current.tmp"
mv -T "$root/.current.tmp" "$root/current"

if [ "$mode" = sync ]; then
  echo "$gen"
  exit 0
fi

# update: svscanが生きていて、liveが初期化済みの場合のみ
if [ -p "$XDG_RUNTIME_DIR/service/.s6-svscan/control" ] && [ -e "$live/compiled" ]; then
  old="$(readlink -f "$live/compiled")"
  if [ "$old" != "$gen" ]; then
    s6-rc-update -t 10000 -l "$live" "$gen"
  fi
fi

# GC: 稼働中liveが参照している世代と最新世代以外を削除
keep_live="$(readlink -f "$live/compiled" 2>/dev/null || true)"
for d in "$root"/*/; do
  d="${d%/}"
  [ "$d" = "$gen" ] || [ "$d" = "$keep_live" ] || rm -rf "$d"
done
