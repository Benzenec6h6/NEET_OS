{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.fwupd;
in {
  options.services.fwupd = {
    enable = mkEnableOption "Firmware update daemon (fwupd)";

    package = mkOption {
      type = types.package;
      default = pkgs.fwupd;
      description = "使用する fwupd パッケージ";
    };
  };

  config = mkIf cfg.enable {
    # 1. 管理コマンド (fwupdmgr など) を PATH に含める
    environment.systemPackages = [cfg.package];

    # 2. D-Bus サービス・ポリシーの登録
    services.dbus.packages = [cfg.package];

    # 3. リポジトリ設定 (LVFS など) やプラグイン設定の配置
    # パッケージ既定の設定ファイル一式を /etc/fwupd に配置
    # (ESP は /boot にマウントされていれば fwupd が自動検出します)
    environment.etc."fwupd".source = "${cfg.package}/etc/fwupd";

    # 4. 状態・キャッシュディレクトリの生成
    system.stateDirectories = [
      {
        path = "/var/lib/fwupd";
        mode = "0755";
        user = "root";
        group = "root";
      }
      {
        path = "/var/cache/fwupd";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # 5. s6-rc サービス定義
    system.s6-rc.services.fwupd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ optional config.neet.security.polkit.enable "polkitd";

      # --no-auto-shutdown: アイドル時の自動終了を抑止し s6-rc で安定して常駐させる
      run = ''
        #!/bin/execlineb -P
        ${cfg.package}/libexec/fwupd/fwupd --no-auto-shutdown
      '';

      # s6-log によるログ収集
      log.enable = true;
    };
  };
}
