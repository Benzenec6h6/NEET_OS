{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.hardware.keyboard;

  # バイナリキーマップのビルド
  binaryKeyMap =
    pkgs.runCommand "bkeymap" {
      nativeBuildInputs = [pkgs.buildPackages.kbd];
      preferLocalBuild = true;
    } ''
      loadkeys --bkeymap "${cfg.keyMap}" > $out
    '';
in {
  options.hardware.keyboard = {
    enable = lib.mkEnableOption "Keyboard keymap configuration" // {default = true;};
    keyMap = lib.mkOption {
      type = lib.types.str;
      default = "us";
      example = "jp106";
      description = "Console keymap";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. Stage 1 (Initrd) へキーマップバイナリを同梱
    boot.initrd.extraContents = [
      {
        source = binaryKeyMap;
        target = "/etc/bkeymap";
      }
    ];

    # 2. Stage 2 (s6-rc) でのロード
    system.s6-rc.services.loadkmap = {
      type = "oneshot";
      up = ''
        #!/bin/execlineb -P
        if { test -c /dev/tty0 }
        redirfd -r 0 ${binaryKeyMap}
        ${pkgs.busybox}/bin/busybox loadkmap
      '';
    };
  };
}
