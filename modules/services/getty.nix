{
  config,
  lib,
  pkgs,
  ...
}: let
  # boot.consoles (["ttyS0", "tty1"] など) を元に s6-rc サービスを自動生成
  mkGettyService = tty: {
    name = "getty-${tty}";
    value = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        # ここで agetty / getty を起動
        # (自動ログインさせたい場合は -a root や -l /bin/sh 等を付与)
        getty 115200 ${tty}
      '';
    };
  };
in {
  config = {
    # boot.consoles の数だけサービスを動的に生やす
    system.s6-rc.services = builtins.listToAttrs (map mkGettyService config.boot.consoles);
  };
}
