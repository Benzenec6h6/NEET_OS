{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.uki;

  # アーキテクチャに応じた Stub ファイル名を決定 (x86_64 -> x64, aarch64 -> aa64)
  efiArch =
    if pkgs.stdenv.hostPlatform.isx86_64
    then "x64"
    else if pkgs.stdenv.hostPlatform.isAarch64
    then "aa64"
    else if pkgs.stdenv.hostPlatform.isx86_32
    then "ia32"
    else throw "Unsupported architecture for UKI";

  # ★ pkgs.systemd (フル版) を使用する
  stubPath = "${pkgs.systemd}/lib/systemd/boot/efi/linux${efiArch}.efi.stub";

  cmdlineText = "${toString config.boot.kernelParams}";

  ukiBinary =
    pkgs.runCommand "neet-os-uki.efi" {
      nativeBuildInputs = [pkgs.binutils-unwrapped pkgs.gawk pkgs.file];
    } ''
      printf 'NAME="NEET OS"\nID=neet-os\nPRETTY_NAME="NEET OS"\n' > os-release.txt
      printf '%s' ${lib.escapeShellArg cmdlineText} > cmdline.txt

      stub="${stubPath}"
      initrd="${config.system.build.initrd}/initrd"
      kernel="${config.boot.kernelPackages.kernel}/bzImage"

      align=$(objdump -p "$stub" | awk '/^SectionAlignment/ { print "0x"$2 }')
      last=$(objdump -h "$stub" | awk 'NF==7 && $1 ~ /^[0-9]+$/ { e = strtonum("0x"$3) + strtonum("0x"$4); if (e > m) m = e } END { printf "0x%x", m }')
      base=$(( (last + align - 1) / align * align ))

      osrel=$base
      cmdline=$(( osrel + 0x10000 ))
      initrd_vma=$(( cmdline + 0x10000 ))
      initrd_size=$(stat -Lc %s "$initrd")
      linux_vma=$(( (initrd_vma + initrd_size + 0xFFFFF) / 0x100000 * 0x100000 ))

      objcopy \
        --add-section .osrel=os-release.txt --change-section-vma .osrel=$(printf 0x%x $osrel) \
        --add-section .cmdline=cmdline.txt  --change-section-vma .cmdline=$(printf 0x%x $cmdline) \
        --add-section .initrd="$initrd"     --change-section-vma .initrd=$(printf 0x%x $initrd_vma) \
        --add-section .linux="$kernel"      --change-section-vma .linux=$(printf 0x%x $linux_vma) \
        "$stub" "$out"

      # ---- 検証: セクションの重なりと PE 形式 ----
      objdump -h "$out"
      objdump -h "$out" | awk '
        NF==7 && $1 ~ /^[0-9]+$/ {
          s = strtonum("0x"$4); e = s + strtonum("0x"$3)
          if (s < prev) { printf "OVERLAP: %s starts at 0x%x < 0x%x\n", $2, s, prev; bad = 1 }
          prev = e
        }
        END { exit bad }'
      file "$out" | grep -q 'PE32+'
    '';
in {
  options.boot.uki = {
    enable = lib.mkEnableOption "Unified Kernel Image for NEET OS";
  };

  config = lib.mkIf cfg.enable {
    system.build.uki = ukiBinary;
  };
}
