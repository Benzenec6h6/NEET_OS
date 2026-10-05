{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.mdevd;
  gidOf = name: toString (config.neet.gids.${name} or 0);

  mdevd-disk = pkgs.writeScriptBin "mdevd-disk.sh" (builtins.readFile ./mdevd-disk.sh);
  isMdevdStage2 = config.services.deviceManager == "mdevd";
in {
  options.services.mdevd = {
    rules = mkOption {
      type = types.lines;
      default = "";
      description = "mdev.conf の内容 (Stage 1 / Stage 2 共通)";
    };
  };

  config = mkMerge [
    # ==============================================================
    # 1. 常時有効（Stage 1 の initrd で必須な成果物・ルール）
    #    ※ gardendevd 有効時でも initrd はこれらを参照する
    # ==============================================================
    {
      # initrd.nix が参照するスクリプト実体
      system.build.mdevdDisk = mdevd-disk;

      # 各ハードウェア（uinput, i2c等）で追加された rules とマージされる基本ルール
      services.mdevd.rules = lib.mkDefault ''
        # ブロックデバイスイベント捕捉ルール (initrd/Stage2共通)
        -SUBSYSTEM=block;.* 0:0 660 */bin/mdevd-disk.sh

        -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"

        SUBSYSTEM=net;ACTION=add;.* 0:0 660 @ip link set $INTERFACE up

        null        0:0 666
        zero        0:0 666
        full        0:0 666
        random      0:0 444
        urandom     0:0 444
        tty         0:0 666
        console     0:0 600
        ptmx        0:0 666

        input/.*    0:${gidOf "input"} 660
        dri/.*      0:${gidOf "video"} 660
        snd/.*      0:${gidOf "video"} 660
        video[0-9]+ 0:${gidOf "video"} 660

        tun         0:0 660 =net/
        sd[a-z].*   0:0 660
        vd[a-z].*   0:0 660
        nvme[0-9]n[0-9].*  0:0 660
        mmcblk[0-9].*      0:0 660
      '';
    }

    # ==============================================================
    # 2. Stage 2 で mdevd が選ばれたときだけ有効化する設定
    # ==============================================================
    (mkIf isMdevdStage2 {
      environment.systemPackages = [
        pkgs.pkgsStatic.mdevd
        pkgs.pkgsStatic.kmod
        pkgs.pkgsStatic.iproute2
        mdevd-disk
      ];

      # Stage 2 用の /etc/mdev.conf を配置
      environment.etc."mdev.conf".text = cfg.rules;

      # Stage 2 用 s6-rc サービス (共通名 devd で登録)
      system.s6-rc.services = {
        devd = {
          type = "longrun";
          run = ''
            #!/bin/execlineb -P
            export PATH /bin:${pkgs.pkgsStatic.mdevd}/bin:${pkgs.pkgsStatic.kmod}/bin
            mdevd -O 4 -f /etc/mdev.conf
          '';
        };

        devd-coldplug = {
          type = "oneshot";
          dependencies = ["devd"];
          up = ''
            #!/bin/execlineb -P
            ${pkgs.pkgsStatic.mdevd}/bin/mdevd-coldplug
          '';
        };
      };
    })
  ];
}
