#!/usr/bin/env bash
set -euo pipefail

# 必須環境変数のチェック
: "${out:?out must be set}"
: "${stage2Init:?stage2Init must be set}"
: "${systemPath:?systemPath must be set}"
: "${etc:?etc must be set}"
: "${kernel:?kernel must be set}"
: "${initrd:?initrd must be set}"
: "${kernelParams:?kernelParams must be set}"
: "${bootspecWrite:?bootspecWrite must be set}"
: "${hostSystem:?hostSystem must be set}"
: "${kernelVersion:?kernelVersion must be set}"

mkdir -p "$out"

# 1. 基本システムリンク
ln -s "$stage2Init" "$out/init"
ln -s "$systemPath" "$out/system-path"
ln -s "$etc" "$out/etc"

# 2. グラフィックスドライバ (rebuild.sh 判定用 / オプション)
if [ -n "${graphicsDrivers:-}" ]; then
  ln -s "$graphicsDrivers" "$out/graphics-drivers"
fi
if [ -n "${graphicsDrivers32:-}" ]; then
  ln -s "$graphicsDrivers32" "$out/graphics-drivers-32bit"
fi

# 3. ブート用ファイル (Kernel / initrd)
# カーネル
if [ -f "$kernel/bzImage" ]; then
  ln -s "$kernel/bzImage" "$out/kernel"
else
  ln -s "$kernel" "$out/kernel"
fi

# initrd: ディレクトリ内の実ファイル (initrd) を指す
if [ -f "$initrd/initrd" ]; then
  ln -s "$initrd/initrd" "$out/initrd"
else
  ln -s "$initrd" "$out/initrd"
fi

# カーネルパラメータ (旧互換用テキスト)
echo "$kernelParams" > "$out/kernel-params"

# 4. UKI (Unified Kernel Image / オプション)
EXTRA_BOOTSPEC_ARGS=()
if [ -n "${uki:-}" ]; then
  ln -s "$uki" "$out/uki.efi"
  EXTRA_BOOTSPEC_ARGS+=(--uki "$out/uki.efi")
fi

# 5. Bootspec (boot.json) の生成
"$bootspecWrite" \
  --system "$hostSystem" \
  --kernel "$out/kernel" \
  --initrd "$out/initrd" \
  --init "$out/init" \
  --kernel-params "$kernelParams" \
  --label "NEET_OS (Linux $kernelVersion)" \
  --toplevel "$out" \
  "${EXTRA_BOOTSPEC_ARGS[@]}" \
  --out "$out/boot.json"
