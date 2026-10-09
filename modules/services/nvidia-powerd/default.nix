{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.nvidia-powerd;
  # NVIDIAドライバパッケージの参照（NEET_OSのハードウェア設定に合わせて調整してください）
  nvidiaPkg = config.hardware.nvidia.package;
in {
  options.services.nvidia-powerd = {
    enable = lib.mkEnableOption "NVIDIA Dynamic Boost (nvidia-powerd) service";

    package = lib.mkOption {
      type = lib.types.package;
      default = nvidiaPkg;
      defaultText = lib.literalExpression "config.hardware.nvidia.package";
      description = "nvidia-powerdを含むNVIDIAドライバパッケージ";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.hardware.nvidia.enable or false;
        message = "services.nvidia-powerd モジュールには hardware.nvidia.enable = true が必要です。";
      }
      {
        assertion = lib.versionAtLeast cfg.package.version "510.39.01";
        message = "NVIDIA Dynamic Boost機能にはバージョン 510.39.01 以降のNVIDIAドライバが必要です。";
      }
    ];

    # dbus.nix の `services.dbus.packages` に D-Bus 用の設定ファイルを登録
    services.dbus.packages = [cfg.package.bin];

    # s6-rc を使った longrun サービスの定義
    system.s6-rc.services.nvidia-powerd = {
      type = "longrun";
      dependencies = ["dbus"]; # D-Busデーモン起動後に実行
      run = ''
        #!/bin/execlineb -P
        redirfd -w 1 /dev/null
        redirfd -r 0 /dev/null
        # nvidia-powerd は内部で lscpu を使用するため path に util-linux を通す
        importpath { PATH }
        with-contenv
        export PATH "${pkgs.util-linux}/bin:$PATH"

        ${cfg.package.bin}/bin/nvidia-powerd
      '';
    };
  };
}
