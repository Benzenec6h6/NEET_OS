{
  config,
  lib,
  ...
}: let
  cfg = config.services.deviceManager;
in {
  options.services.deviceManager = lib.mkOption {
    type = lib.types.enum ["mdevd" "gardendevd" "none"];
    default = "mdevd";
    description = "Stage 2 で使用するデバイスイベントマネージャ。";
  };

  # デバイスマネージャが有効かどうかを他サービスが判定するための簡易フラグ
  options.services.deviceManagerEnable = lib.mkOption {
    type = lib.types.bool;
    readOnly = true;
    default = cfg != "none";
  };
}
