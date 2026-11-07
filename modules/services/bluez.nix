{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.bluetooth;
in {
  options.services.bluetooth = {
    enable = mkEnableOption "Bluetooth support (BlueZ daemon)";
  };

  config = mkIf cfg.enable {
    # 1. ユーザー空間ツール (bluetoothctl など)
    environment.systemPackages = [pkgs.bluez];

    # 2. D-Bus ポリシーの登録 (org.bluez をシステムバスで許可)
    services.dbus.packages = [pkgs.bluez];

    # 3. 設定ファイル (必要に応じて自動電源ONなどを設定)
    environment.etc."bluetooth/main.conf".text = ''
      [General]
      AutoEnable=true
    '';

    # 4. s6-rc サービス定義 (bluetoothd)
    system.s6-rc.services.bluetoothd = {
      type = "longrun";
      dependencies = ["dbus"]; # D-Bus が必須
      run = ''
        #!/bin/execlineb -P
        ${pkgs.bluez}/libexec/bluetooth/bluetoothd --nodetach
      '';
    };
  };
}
