{
  pkgs,
  lib,
  config,
  ...
}:
with lib; let
  cfg = config.services.mdevd;
  gidOf = name: toString (config.neet.gids.${name} or 0);

  diskScriptBinPath = lib.makeBinPath [
    pkgs.pkgsStatic.util-linux
    pkgs.pkgsStatic.busybox
  ];

  mdevd-disk-script = pkgs.replaceVarsWith {
    src = ./mdevd-disk.sh;
    replacements = {
      binPath = diskScriptBinPath;
    };
    isExecutable = true;
  };

  # /bin/mdevd-disk.sh として配置できるパッケージ
  mdevd-disk = pkgs.runCommand "mdevd-disk" {} ''
    mkdir -p $out/bin
    cp ${mdevd-disk-script} $out/bin/mdevd-disk.sh
    chmod 755 $out/bin/mdevd-disk.sh
  '';

  isMdevdStage2 = config.services.deviceManager == "mdevd";
in {
  options = {
    # Stage 1 専用（initrd 用の極小ルール）
    boot.initrd.mdevd = {
      rules = mkOption {
        type = types.lines;
        default = "";
        description = "Stage 1 (initrd) 専用の mdev.conf。ディスクと基本ノードのみ。";
      };
    };

    # Stage 2 専用（OS 稼働時用のフルルール）
    services.mdevd = {
      rules = mkOption {
        type = types.lines;
        default = "";
        description = "Stage 2 専用の mdev.conf。デバイスManagerが mdevd の時のみ使用。";
      };
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
      boot.initrd.mdevd.rules = ''
        # ブロックデバイスの検出 (LUKS やルートマウントに必須)
        -SUBSYSTEM=block;.* 0:0 660 */bin/mdevd-disk.sh

        -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"

        null        0:0 666
        zero        0:0 666
        full        0:0 666
        console     0:0 600
        ptmx        0:0 666
        tty[0-9]*   0:0 660

        sd[a-z].*          0:0 660
        vd[a-z].*          0:0 660
        nvme[0-9]n[0-9].*  0:0 660
        mmcblk[0-9].*      0:0 660
      '';
    }

    # --------------------------------------------------
    # Stage 2 (稼働時) のフルルール
    # --------------------------------------------------
    {
      # 基本ルール（audio, video, input 等は Stage 2 だけが持てば良い）
      services.mdevd.rules = ''
        -SUBSYSTEM=block;.* 0:0 660 */bin/mdevd-disk.sh
        -$MODALIAS=.* 0:0 660 @modprobe --quiet "$MODALIAS"
        -SUBSYSTEM=net;.* 0:0 660 @ip link set $INTERFACE up

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
        snd/.*      0:${gidOf "audio"} 660
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
          notification-fd = 3;
          log.enable = true;
          run = ''
            #!/bin/execlineb -P
            export PATH /bin:${pkgs.pkgsStatic.mdevd}/bin:${pkgs.pkgsStatic.kmod}/bin
            mdevd -D 3 -O 4 -f /etc/mdev.conf
          '';
        };

        devd-coldplug = {
          type = "oneshot";
          dependencies = ["devd"];
          up = ''
            #!/bin/execlineb -P
            ${pkgs.pkgsStatic.mdevd}/bin/mdevd-coldplug -O 4
          '';
        };
      };
    })
  ];
}
