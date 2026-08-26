{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.mdevd;
  gidOf = name: toString config.neet.gids.${name};
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
      pkgs.pkgsStatic.iproute2
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

    environment.etc."s6-scan/udhcpc-eth0/run" = {
      text = ''
        #!/bin/execlineb -P
        # PATH の通し（busybox や s6 のバイナリパス）
        export PATH /bin:${pkgs.pkgsStatic.s6}/bin

        # -f : フォアグラウンドで常駐（s6 に監視させるため必須）
        # -i : インターフェース指定
        # -p : PID ファイルの場所
        exec udhcpc -f -i eth0
      '';
      mode = "0555";
    };

    # ルールのデフォルト定義
    services.mdevd.rules = lib.mkDefault ''
      # 1. モジュールの自動ロード
      -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"

      SUBSYSTEM=net;ACTION=add;.* 0:0 660 @ip link set $INTERFACE up

      # 2. 基本的なデバイス
      null        0:0 666
      zero        0:0 666
      full        0:0 666
      random      0:0 444
      urandom     0:0 444
      tty         0:0 666
      console     0:0 600
      ptmx        0:0 666

      # 3. 各サブシステムのパーミッション (パス含めで指定)
      input/.*    0:${gidOf "input"} 660
      dri/.*      0:${gidOf "video"} 660
      video[0-9]+ 0:${gidOf "video"} 660

      tun         0:0 660 =net/
      sd[a-z].*   0:0 660
    '';
  };
}
