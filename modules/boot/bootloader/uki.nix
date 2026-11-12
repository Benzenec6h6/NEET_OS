{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.uki;

  # アーキテクチャに応じた Stub ファイル名を決定
  efiArch =
    if pkgs.stdenv.hostPlatform.isx86_64
    then "x64"
    else if pkgs.stdenv.hostPlatform.isAarch64
    then "aa64"
    else if pkgs.stdenv.hostPlatform.isx86_32
    then "ia32"
    else throw "Unsupported architecture for UKI";

  stubPath = "${pkgs.systemd}/lib/systemd/boot/efi/linux${efiArch}.efi.stub";
  cmdlineText = toString config.boot.kernelParams;

  inieet = pkgs.callPackage ../../pkgs/inieet {};

  osReleaseFile = pkgs.writeText "os-release" ''
    NAME="NEET OS"
    ID=neet-os
    PRETTY_NAME="NEET OS"
  '';

  ukiBinary =
    pkgs.runCommand "neet-os-uki.efi" {
      nativeBuildInputs = [inieet.neetUki];
    } ''
      neet-uki \
        --stub "${stubPath}" \
        --osrel "${osReleaseFile}" \
        --cmdline ${lib.escapeShellArg cmdlineText} \
        --initrd "${config.system.build.initrd}/initrd" \
        --linux "${config.boot.kernelPackages.kernel}/bzImage" \
        --out "$out"
    '';
in {
  options.boot.uki = {
    enable = lib.mkEnableOption "Unified Kernel Image for NEET OS";
  };

  config = lib.mkIf cfg.enable {
    system.build.uki = ukiBinary;
  };
}
