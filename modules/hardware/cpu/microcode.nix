{
  config,
  lib,
  pkgs,
  ...
}: let
  # options の共通化ヘルパー
  mkVendorOptions = vendorName: defaultPackage: {
    updateMicrocode = lib.mkOption {
      default = false;
      type = lib.types.bool;
      description = "Update the CPU microcode for ${vendorName} processors.";
    };

    microcodePackage = lib.mkOption {
      default = defaultPackage;
      type = lib.types.package;
    };
  };

  # config の共通化ヘルパー
  mkInitrdConfig = cfg: imgFile:
    lib.mkIf cfg.updateMicrocode {
      boot.initrd.prepend = lib.mkOrder 1 ["${cfg.microcodePackage}/${imgFile}"];
    };
in {
  # 1. options を明示的に登録（これで cpu 属性が確実に存在することになる）
  options.hardware.cpu = {
    amd = mkVendorOptions "AMD" pkgs.microcode-amd;
    intel = mkVendorOptions "Intel" pkgs.microcode-intel;
  };

  # 2. config 側でそれぞれの設定を生成
  config = lib.mkMerge [
    (mkInitrdConfig config.hardware.cpu.amd "amd-ucode.img")
    (mkInitrdConfig config.hardware.cpu.intel "intel-ucode.img")
  ];
}
