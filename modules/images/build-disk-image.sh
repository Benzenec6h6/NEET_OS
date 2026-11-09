#!/usr/bin/env bash
set -euo pipefail

# 必須環境変数のチェック
: "${out:?out must be set}"
: "${toplevel:?toplevel must be set}"
: "${rootfs:?rootfs must be set}"
: "${diskPlan:?diskPlan must be set}"
: "${diskSizeM:?diskSizeM must be set}"
: "${espMount:?espMount must be set}"
: "${bootloader:?bootloader must be set}" # "limine" または "efistub"

echo "build-disk-image: assembling disk image (${diskSizeM}M, plan: ${diskPlan})..."

# ==========================================
# 1. ブートローダのファイルを「完成後のルート階層」の ESP の位置に用意する
#    （パーティション分割・mkfs・書き込みは disk-setup が plan に従って行う）
# ==========================================
layer="$PWD/layer"
esp="${layer}${espMount}"
mkdir -p "$esp/EFI/BOOT"

if [ "$bootloader" = "limine" ]; then
  : "${liminePkg:?liminePkg must be set for limine}"
  echo "build-disk-image: configuring Limine..."

  mkdir -p "$esp/kernels"
  cp "${liminePkg}/share/limine/BOOTX64.EFI" "$esp/EFI/BOOT/BOOTX64.EFI"
  cp "${toplevel}/kernel" "$esp/kernels/gen-1-vmlinuz"
  cp "${toplevel}/initrd" "$esp/kernels/gen-1-initrd"

  cat <<EOT > "$esp/limine.conf"
timeout: 5

/NEET OS (Generation 1 - Current)
    protocol: linux
    kernel_path: boot():/kernels/gen-1-vmlinuz
    module_path: boot():/kernels/gen-1-initrd
    cmdline: init=${toplevel}/init $(cat "${toplevel}/kernel-params")
EOT

elif [ "$bootloader" = "efistub" ]; then
  if [ -n "${ukiFile:-}" ]; then
    echo "build-disk-image: configuring pure UKI direct boot..."
    cp "${ukiFile}" "$esp/EFI/BOOT/BOOTX64.EFI"
  else
    : "${uefiShellPkg:?uefiShellPkg must be set}"
    echo "build-disk-image: configuring EFISTUB via UEFI Shell..."

    mkdir -p "$esp/EFI/NEET"
    cp "${toplevel}/kernel" "$esp/EFI/NEET/gen-1-vmlinuz.efi"
    cp "${toplevel}/initrd" "$esp/EFI/NEET/gen-1-initrd.img"
    cp "${uefiShellPkg}" "$esp/EFI/BOOT/BOOTX64.EFI"

    cat <<EOT > "$esp/startup.nsh"
\EFI\NEET\gen-1-vmlinuz.efi initrd=\EFI\NEET\gen-1-initrd.img init=${toplevel}/init $(cat "${toplevel}/kernel-params")
EOT
  fi
else
  echo "build-disk-image: error: unsupported bootloader '$bootloader'" >&2
  exit 1
fi

# ==========================================
# 2. disk-setup でイメージ化
#    --tree は後ろが前を上書き。rootfs（読み取り専用）の上に ESP 用レイヤを重ねる
# ==========================================
args=(image "$diskPlan" --out "$out" --size-m "$diskSizeM"
  --tree "$rootfs" --tree "$layer" --work "$PWD/work")
if [ -n "${diskName:-}" ]; then
  args+=(--disk "$diskName")
fi

disk-setup "${args[@]}"

echo "build-disk-image: disk image successfully created at $out"
