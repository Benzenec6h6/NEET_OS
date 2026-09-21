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
        # util-linux の agetty を使用する場合: TTY名 -> ボーレート の順
        # 画面制御（VT）や自動ログイン等のオプションも必要に応じて付与
        ${pkgs.util-linux}/bin/agetty ${tty} 115200
      '';
    };
  };
in {
  config = {
    # boot.consoles の数だけサービスを動的に生やす
    system.s6-rc.services = builtins.listToAttrs (map mkGettyService config.boot.consoles);
  };
}
