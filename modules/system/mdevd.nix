{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.mdevd;
in {
  options.services.mdevd = {
    enable = mkEnableOption "mdevd";
    rules = mkOption {
      type = types.lines;
      default = "";
      description = "mdev.confの内容";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      pkgs.pkgsStatic.mdevd
      pkgs.pkgsStatic.kmod # modprobe を確実に用意
    ];

    # mdev.conf の配置
    environment.etc."mdev.conf".text = cfg.rules;

    # s6 サービスとしての定義
    environment.etc."s6-scan/mdevd/run" = {
      text = ''
        #!/bin/execlineb -P
        export PATH /bin:${pkgs.pkgsStatic.mdevd}/bin:${pkgs.pkgsStatic.kmod}/bin:${pkgs.pkgsStatic.s6}/bin

        # readiness 通知を待たずに、mdevd をバックグラウンドで起動し、
        # 少し待ってから coldplug を実行するか、あるいは単に並列実行する

        background {
          # 1秒待ってから coldplug を実行（svwait が効かない場合の暫定処置）
          foreground { sleep 1 }
          mdevd-coldplug
        }

        mdevd -O 4 -f /etc/mdev.conf
      '';
      mode = "0555";
    };

    environment.etc."s6-scan/mdevd/notification-fd".text = "4\n";

    # ルールのデフォルト定義
    services.mdevd.rules = lib.mkDefault ''
      # 1. モジュールの自動ロード (MODALIASに基づく) - ★最重要
      -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"

      # 2. 基本的なデバイスのパーミッション設定
      null        0:0 666
      zero        0:0 666
      full        0:0 666
      random      0:0 444
      urandom     0:0 444
      tty         0:5 666
      console     0:5 600
      ptmx        0:5 666

      # 3. 各サブシステムごとのディレクトリ分離・パーミッション指定
      event[0-9]+ 0:0 660 =input/
      mice        0:0 660 =input/
      card[0-9]+  0:0 660 =dri/
      tun         0:0 666 =net/
      sd[a-z].*   0:6 660
    '';
  };
}
