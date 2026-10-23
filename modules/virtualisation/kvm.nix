{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.virtualisation.kvm;
  kvmGid = toString (config.neet.gids.kvm or "kvm");
in {
  options.virtualisation.kvm = {
    enable = lib.mkEnableOption "KVM host support for running virtual machines";

    platform = lib.mkOption {
      type = lib.types.enum ["all" "intel" "amd"];
      default = "all";
      description = ''
        CPU ベンダーに応じた KVM モジュール。
        "all" の場合、両方ロードを試みます（非対応側はカーネルが自動で無視するため安全です）。
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. KVM カーネルモジュールのロード
    boot.kernelModules =
      ["kvm"]
      ++ lib.optionals (cfg.platform == "intel" || cfg.platform == "all") ["kvm-intel"]
      ++ lib.optionals (cfg.platform == "amd" || cfg.platform == "all") ["kvm-amd"];

    # 2. mdevd 用のデバイスノード権限ルール
    # （mdevd が有効なときだけ /etc/mdev.conf にマージされる）
    services.mdevd.rules = ''
      kvm 0:${kvmGid} 660
    '';

    # 3. gardendevd (udev) 用のルール
    # （gardendevd が有効なときだけ 99-local-extra.rules にマージされる）
    services.udev.extraRules = ''
      KERNEL=="kvm", GROUP="kvm", MODE="0660"
    '';

    # 4. ホストとして VM を操作・管理するための基本ツール
    environment.systemPackages = [
      pkgs.qemu
    ];
  };
}
