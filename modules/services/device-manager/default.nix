{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.services.deviceManager;
in {
  imports = [
    ./gardendevd
    ./mdevd
  ];

  options.services.deviceManager = lib.mkOption {
    type = lib.types.enum ["mdevd" "gardendevd" "none"];
    default = "mdevd";
    description = "Stage 2 で使用するデバイスイベントマネージャ。";
  };

  options.services.deviceManagerEnable = lib.mkOption {
    type = lib.types.bool;
    readOnly = true;
    default = cfg != "none";
  };

  # ★ 追加: 全 Wayland WM や X11 から共通で使える udev API スタブ
  options.services.deviceManagerUdevApi = lib.mkOption {
    type = lib.types.nullOr lib.types.package;
    readOnly = true;
    default =
      if cfg == "gardendevd"
      then pkgs.libudev-garden
      else if cfg == "mdevd"
      then pkgs.libudev-zero
      else null;
    description = "非 systemd 環境用 libudev 互換スタブパッケージ";
  };

  # ★ 追加: スタブ版 libudev を注入済みの共通 libinput
  options.services.deviceManagerLibinput = lib.mkOption {
    type = lib.types.package;
    readOnly = true;
    default =
      if config.services.deviceManagerUdevApi != null
      then
        pkgs.libinput.override {
          udev = config.services.deviceManagerUdevApi;
          wacomSupport = false;
        }
      else pkgs.libinput;
    description = "デバイスマネージャに適合させた libinput";
  };

  config = {
    system.s6-rc.services.device-manager = {
      type = "bundle";
      contents =
        {
          mdevd = ["mdevd" "mdevd-coldplug"];
          gardendevd = ["gardendevd" "gardendevd-coldplug"];
          none = [];
        }.${
          cfg
        };
    };
  };
}
