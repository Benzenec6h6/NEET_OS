{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.upower;
in {
  options.services.upower = {
    enable = mkEnableOption "UPower daemon for power and battery management";

    package = mkOption {
      type = types.package;
      default = pkgs.upower;
      description = "UPower パッケージ";
    };
  };

  config = mkIf cfg.enable {
    # 1. CLI ツール (upower) の利用
    environment.systemPackages = [cfg.package];

    # 2. D-Bus システムバス設定の取り込み
    # /share/dbus-1/system.d/org.freedesktop.UPower.conf を D-Bus に認識させる
    services.dbus.packages = [cfg.package];

    # 3. 状態保存ディレクトリの作成
    # UPower は /var/lib/upower に充放電履歴などを保存します
    system.stateDirectories = [
      {
        path = "/var/lib/upower";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # 4. s6-rc サービス定義 (upowerd)
    system.s6-rc.services.upower = {
      type = "longrun";
      dependencies = ["dbus"]; # D-Bus が必須
      run = ''
        #!/bin/execlineb -P
        ${cfg.package}/libexec/upowerd
      '';
    };
  };
}
