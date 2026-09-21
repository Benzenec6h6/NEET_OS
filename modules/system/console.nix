{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.boot.console;

  # ビルド時にバイナリキーマップを生成
  binaryKeyMap =
    pkgs.runCommand "bkeymap" {
      nativeBuildInputs = [pkgs.buildPackages.kbd];
    } ''
      loadkeys --bkeymap "${cfg.keyMap}" > $out
    '';
in {
  options.boot.console = {
    enable = lib.mkEnableOption "Console keymap configuration" // {default = true;};

    keyMap = lib.mkOption {
      type = lib.types.str;
      default = "us";
      example = "jp106";
      description = "Keyboard map for virtual consoles (e.g. jp106, us)";
    };
  };

  config = lib.mkIf cfg.enable {
    # 方法A: s6-rc のワンショットサービスとして登録する場合
    system.s6-rc.services.loadkmap = {
      type = "oneshot";
      up = ''
        #!/bin/sh
        # /dev/tty0 (仮想コンソール) が存在する場合のみキーマップを流し込む
        if [ -c /dev/tty0 ]; then
          ${pkgs.busybox}/bin/busybox loadkmap < ${binaryKeyMap}
        fi
      '';
    };

    # (もしシリアル端末等で mdevd 側のパーミッション調整が必要なら)
    # services.mdevd ...
  };
}
