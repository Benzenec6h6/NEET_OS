{
  config,
  pkgs,
  lib,
  ...
}: {
  # 1. オプションの宣言 (これがないと代入できない)
  options = {
    system.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
    };
    system.activationScript = lib.mkOption {
      type = lib.types.package;
      internal = true;
      description = "システム起動時に実行されるスクリプト";
    };
  };

  # 2. オプションへの代入
  config.system.activationScript = pkgs.writeTextFile {
    name = "activate";
    executable = true;
    destination = "/bin/activate"; # どこに配置するか明示（任意）
    text = ''
      #!/bin/execlineb -P
      # 1. Rustでファイル群を構築
      foreground {
        ${config.system.etc.bin}/bin/system-init
        ${config.system.etc.package}
        ${config.system.path}
        ${config.boot.kernelPackages.kernel}
      }
      # 2. 必要に応じて here に追加の処理を書く
      true
    '';
  };
}
