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

  cmdlineText = "init=${config.system.build.earlyInit}/bin/early-init ${toString config.boot.kernelParams}";

  ukiBinary =
    pkgs.runCommand "neet-os-uki.efi" {
      nativeBuildInputs = [pkgs.binutils-unwrapped];
    } ''
      echo -n "${cmdlineText}" > cmdline.txt
      echo -n "NAME=\"NEET OS\"\nID=neet-os\nPRETTY_NAME=\"NEET OS\"" > os-release.txt

      # objcopy で UKI バイナリを生成
      objcopy \
        --add-section .osrel="os-release.txt" --change-section-vma .osrel=0x20000 \
        --add-section .cmdline="cmdline.txt"  --change-section-vma .cmdline=0x30000 \
        --add-section .initrd="${config.system.build.initrd}/initrd" --change-section-vma .initrd=0x40000 \
        --add-section .linux="${config.boot.kernelPackages.kernel}/bzImage" --change-section-vma .linux=0x4000000 \
        "${stubPath}" "$out"
    '';
in {
  options.boot.uki = {
    enable = lib.mkEnableOption "Unified Kernel Image for NEET OS";
  };

  config = lib.mkIf cfg.enable {
    system.build.uki = ukiBinary;
  };
}
