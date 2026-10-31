#!/usr/bin/env bash
set -euo pipefail

# Nix のオプションから注入されるデフォルト値
DEFAULT_RECIPIENTS=(@defaultRecipients@)
IDENTITY="${NEET_SECRET_IDENTITY:-@defaultIdentity@}"

# 引数解析
EXTRA_RECIPIENTS=()
TARGET_FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    -r|--recipient)
      EXTRA_RECIPIENTS+=("-r" "$2")
      shift 2
      ;;
    -i|--identity)
      IDENTITY="$2"
      shift 2
      ;;
    -h|--help)
      echo "Usage: neet-secret-edit [-i <identity_file>] [-r <recipient_key>...] <target.age>"
      exit 0
      ;;
    *)
      TARGET_FILE="$1"
      shift
      ;;
  esac
done

if [[ -z "$TARGET_FILE" ]]; then
  echo "Error: 対象の .age ファイルを指定してください。" >&2
  exit 1
fi

# 一時ファイルの作成 (RAM ディスク /dev/shm があれば優先)
TMP_DIR="${TMPDIR:-/tmp}"
if [[ -d "/dev/shm" && -w "/dev/shm" ]]; then
  TMP_DIR="/dev/shm"
fi
TMP_FILE=$(mktemp "$TMP_DIR/secret.XXXXXX")

# 終了時に必ず平文を抹消
trap 'shred -u "$TMP_FILE" 2>/dev/null || rm -f "$TMP_FILE"' EXIT

# 既存ファイルがある場合は指定の秘密鍵で復号して一時ファイルへ展開
if [[ -f "$TARGET_FILE" ]]; then
  if [[ ! -f "$IDENTITY" ]]; then
    echo "Error: 復号に必要な秘密鍵が見つかりません: $IDENTITY" >&2
    exit 1
  fi
  age -d -i "$IDENTITY" "$TARGET_FILE" > "$TMP_FILE"
fi

# エディタ起動
"${EDITOR:-vim}" "$TMP_FILE"

# 保存・暗号化
mkdir -p "$(dirname "$TARGET_FILE")"

# Nix オプションの鍵 + CLI で追加された鍵をすべて渡す
age "${DEFAULT_RECIPIENTS[@]}" ${EXTRA_RECIPIENTS[@]+"${EXTRA_RECIPIENTS[@]}"} -o "$TARGET_FILE" "$TMP_FILE"

echo "正常に暗号化されました: $TARGET_FILE"
