{
  pkgs,
  lib,
  config,
  ...
}: {
  options.system.activationScript = lib.mkOption {
    type = lib.types.package;
    internal = true;
  };

  config.system.activationScript = pkgs.writeScript "activate" ''
    #!${pkgs.pkgsStatic.execline}/bin/execlineb -P
    export PATH /bin
    # マウント
    foreground { mkdir -p /proc /sys /dev /etc /run /root /var/log }
    foreground { mount -t proc proc /proc }
    foreground { mount -t sysfs sysfs /sys }
    foreground { mount -t devtmpfs devtmpfs /dev }

    # /etc の同期
    foreground { /bin/etc-syncer ${config.system.etcDir} }

    # s6サービスの準備 (s6-svscan用のディレクトリを書き込み可能な /run に作る)
    foreground { rm -rf /run/service }
    foreground { mkdir -p /run/service }
    # runファイルをコピーし、実行権限を付与する
    # ※ 本来は etc-syncer を賢くすべきですが、一旦ここで chmod します
    foreground { /bin/sh -c "cp -rL /etc/s6-scan/* /run/service/" }
    foreground { /bin/sh -c "chmod +x /run/service/*/run" }
  '';
}
