#!/usr/bin/env bash
set -euo pipefail

# 必須環境変数のチェック
: "${out:?out must be set}"
: "${closure:?closure must be set}"
: "${toplevel:?toplevel must be set}"

echo "populate-rootfs: creating rootfs structure..."
mkdir -p "$out/nix/store"

# 1. ストアパスの実体をコピー
echo "populate-rootfs: copying store paths..."
while read -r path; do
  cp -a "$path" "$out/nix/store/$(basename "$path")"
done < "${closure}/store-paths"

# 2. Nix データベースの初期化と登録
echo "populate-rootfs: populating nix database..."
nix-store --store "$out" --load-db < "${closure}/registration"

# 3. 初期プロファイル (第1世代) の作成
echo "populate-rootfs: setting up initial profile..."
mkdir -p "$out/nix/var/nix/profiles"
ln -s "$toplevel" "$out/nix/var/nix/profiles/system-1-link"
ln -s "system-1-link" "$out/nix/var/nix/profiles/system"

# 4. GC ルートの基本ディレクトリと初期リンク
mkdir -p "$out/nix/var/nix/gcroots"
ln -s "/nix/var/nix/profiles/system" "$out/nix/var/nix/gcroots/current-system"

# 5. root ホームディレクトリの作成
mkdir -p -m 0700 "$out/root"
# ESP をマウントするための空ディレクトリ
mkdir -p -m 0755 "$out/boot"
# 6. /nix/var の書き込み権限を確実に付与 (サンドボックス特有の read-only を解除)
chmod -R u+w "$out/nix/var"

echo "populate-rootfs: rootfs successfully created at $out"
