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
  options.boot = {
    console = {
      enable = lib.mkEnableOption "Console keymap configuration" // {default = true;};

      keyMap = lib.mkOption {
        type = lib.types.str;
        default = "us";
        example = "jp106";
        description = "Keyboard map for virtual consoles (e.g. jp106, us)";
      };
    };

    # 1. 画面用 (Virtual Terminal)
    vt = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "グラフィカルコンソール (VT) 出力を有効にするか";
      };

      consoles = lib.mkOption {
        type = lib.types.listOf lib.types.int;
        default = [1];
        example = [1 2 3];
        description = "有効化する仮想端末番号のリスト (/dev/tty<N>)";
      };
    };

    # 2. デバッグ用 (Serial)
    serial = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = "シリアルコンソール (/dev/ttyS* 等) を有効にするか";
      };

      device = lib.mkOption {
        type = lib.types.str;
        default = "ttyS0";
        description = "シリアルコンソールのデバイス名";
      };

      speed = lib.mkOption {
        type = lib.types.int;
        default = 115200;
        description = "シリアル通信速度 (ボーレート)";
      };
    };

    # 3. プライマリ出力先 (getty.nix 等で利用)
    primaryConsole = lib.mkOption {
      type = lib.types.enum ["vt" "serial"];
      default =
        if config.boot.serial.enable
        then "serial"
        else "vt";
      description = "カーネルメッセージ (dmesg) や Stage1 の最優先出力先";
    };
  };

  # ★ config は options と並列（トップレベル）に配置します
  config = lib.mkIf cfg.enable {
    # 方法A: s6-rc のワンショットサービスとして登録する場合
    system.s6-rc.services.loadkmap = {
      type = "oneshot";
      up = ''
        #!/bin/execlineb -P
        if { test -c /dev/tty0 }
        redirfd -r 0 ${binaryKeyMap}
        ${pkgs.busybox}/bin/busybox loadkmap
      '';
    };

    # (もしシリアル端末等で mdevd 側のパーミッション調整が必要なら)
    # services.mdevd ...
  };
}
