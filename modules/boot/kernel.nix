{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    boot.kernelPackages = lib.mkOption {
      default = pkgs.linuxPackages;
      type = lib.types.raw;
      description = "使用するカーネルパッケージ（標準は最新のLTSなど）";
    };

    boot.kernelParams = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "カーネルパラメータ";
    };

    boot.kernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Stage 2 で自動ロードするモジュール";
    };

    system.modulesTree = lib.mkOption {
      type = lib.types.path;
      internal = true;
    };
  };

  config = {
    # カーネル本体と追加モジュールを1つのツリーにまとめる
    system.modulesTree = pkgs.aggregateModules [
      (lib.getOutput "modules" config.boot.kernelPackages.kernel)
    ];

    # デフォルトのカーネルパラメータ（シリアルコンソール等）
    boot.kernelParams = [
      "console=ttyS0"
      "panic=10"
    ];

    # 標準でロードしておくべきモジュール
    boot.kernelModules = ["loop" "atkbd"];
  };
}
