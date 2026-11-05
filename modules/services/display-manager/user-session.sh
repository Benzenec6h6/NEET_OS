exec > /tmp/neet-user-session.log 2>&1
set -x

export PATH="/run/wrappers/bin:/run/current-system/bin:$PATH"

USER_NAME="$(id -un)"
USER_UID="$(id -u)"
export XDG_RUNTIME_DIR="/run/user/$USER_UID"
export HOME="${HOME:-/home/$USER_NAME}"
export XDG_SESSION_TYPE=wayland
export DBUS_SESSION_BUS_ADDRESS="unix:path=$XDG_RUNTIME_DIR/bus"

if [ -S /run/seatd/seatd.sock ]; then
  export SEATD_SOCK=/run/seatd/seatd.sock
fi

SERVICE_DIR="$XDG_RUNTIME_DIR/service"
LIVE_DIR="$XDG_RUNTIME_DIR/s6-rc"
COMPILED_DB="/var/lib/s6-rc/users/$USER_NAME/compiled"
export S6_LIVE_DIR="$LIVE_DIR" # WM -> neet-session-ready に継承される

if [ ! -d "$COMPILED_DB" ]; then
  echo "compiled s6-rc db not found: $COMPILED_DB" >&2
  exit 1
fi

rm -rf "$LIVE_DIR" "$SERVICE_DIR"
mkdir -p "$SERVICE_DIR"

# svscan の準備完了を fd 通知で待つ (polling なし)
fifo="$XDG_RUNTIME_DIR/svscan.ready"
rm -f "$fifo"
mkfifo "$fifo"
s6-svscan -d3 "$SERVICE_DIR" 3>"$fifo" &
SVSCAN_PID=$!
read -r _ < "$fifo" || true
rm -f "$fifo"
# -d 非対応などで即死していたらここで止める
kill -0 "$SVSCAN_PID"

cleanup() {
  set +e
  s6-rc -l "$LIVE_DIR" -da change
  s6-svscanctl -t "$SERVICE_DIR"
  wait "$SVSCAN_PID"
}
trap cleanup EXIT

s6-rc-init -c "$COMPILED_DB" -l "$LIVE_DIR" "$SERVICE_DIR"
s6-rc -l "$LIVE_DIR" -u change top

# graphical-session は WM が neet-session-ready を呼んだ時点で起動する
key="$(basename "${1:-$DEFAULT_SESSION}" .desktop)"
bin="$SESSIONS_DIR/$key"
[ -x "$bin" ] || bin="$SESSIONS_DIR/$DEFAULT_SESSION"
"$bin" || true
