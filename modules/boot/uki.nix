{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.uki;

  # コマンドライン引数の組み立て
  cmdlineText = "init=${config.system.build.earlyInit}/bin/early-init ${toString config.boot.kernelParams}";

  # UKI (PE32+ バイナリ) をビルドする
  ukiBinary =
    pkgs.runCommand "neet-os-uki.efi" {
      nativeBuildInputs = [pkgs.binutils-unwrapped];
    } ''
      # systemd-boot が提供する stub バイナリを利用
      STUB="${pkgs.systemdMinimal}/lib/systemd/boot/efi/linuxx64.efi.stub"

      echo -n "${cmdlineText}" > cmdline.txt
      echo -n "NAME=\"NEET OS\"\nID=neet-os\nPRETTY_NAME=\"NEET OS\"" > os-release.txt

      # 各コンポーネントを PE セクションとしてマージ
      objcopy \
        --add-section .osrel="os-release.txt" --change-section-vma .osrel=0x20000 \
        --add-section .cmdline="cmdline.txt"  --change-section-vma .cmdline=0x30000 \
        --add-section .initrd="${config.system.build.initrd}" --change-section-vma .initrd=0x40000 \
        --add-section .linux="${config.boot.kernelPackages.kernel}/bzImage" --change-section-vma .linux=0x2000000 \
        "$STUB" "$out"
    '';
in {
  options.boot.uki = {
    enable = lib.mkEnableOption "Unified Kernel Image for NEET OS";
  };

  config = lib.mkIf cfg.enable {
    # bootspec-write の呼び出し時に --uki を渡すように連携
    system.build.uki = ukiBinary;
  };
}
