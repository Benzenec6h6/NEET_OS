{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.security.tpm2;
in {
  options.security.tpm2 = {
    enable = mkEnableOption "TPM 2.0 support and tooling";
  };

  config = mkIf cfg.enable {
    # 1. initrd (Stage 1) で TPM と通信するためのカーネルドライバ
    boot.initrd.availableKernelModules = [
      "tpm"
      "tpm_tis" # QEMU や多くのデスクトップ/マザーボード
      "tpm_crb" # Intel PTT / AMD fTPM (ファームウェア TPM)
    ];

    # 2. Stage 2 (システム運用・プロビジョニング時) に必要なツール群
    environment.systemPackages = [
      pkgs.tpm2-tools
      pkgs.age
    ];
  };
}
