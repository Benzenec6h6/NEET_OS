{
  config,
  lib,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;
in {
  imports = [
    ./kernel.nix
    ./initrd.nix
    ./sysctl.nix
    ./limine.nix
    ./secureboot.nix
    ./efistub.nix
    ./uki.nix
  ];

  options.boot = {
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

    # 3. プライマリ出力先
    primaryConsole = lib.mkOption {
      type = lib.types.enum ["vt" "serial"];
      default =
        if config.boot.serial.enable
        then "serial"
        else "vt";
      description = "カーネルメッセージ (dmesg) や Stage1 の最優先出力先";
    };
  };

  config = {
    system.build.kernel = kernel;
  };
}
