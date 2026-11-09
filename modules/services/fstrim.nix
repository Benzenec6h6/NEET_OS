{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.fstrim;
in {
  options.services.fstrim = {
    enable = mkEnableOption "periodic fstrim (discard unused blocks on SSDs/NVMe)";

    package = mkOption {
      type = types.package;
      default = pkgs.util-linux;
      description = "fstrim コマンドを提供するパッケージ";
    };

    interval = mkOption {
      type = types.str;
      default = "@weekly";
      example = "0 3 * * 0";
      description = ''
        fcron で実行する間隔。
        fcron の &bootrun を併用するため、電源停止中に実行時刻が過ぎた場合も次回起動時に実行されます。
      '';
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = ["-av"];
      description = "fstrim に渡すコマンドライン引数 (-av: 全マウント対象・詳細出力)";
    };
  };

  config = mkIf cfg.enable {
    # 手動実行用にも PATH に util-linux を追加
    environment.systemPackages = [cfg.package];

    # fcron が有効であれば systab にタスクを追加
    services.fcron = {
      enable = mkDefault true; # fstrim 有効時は fcron も自動で有効化
      systab = [
        "&bootrun ${cfg.interval} root ${cfg.package}/bin/fstrim ${escapeShellArgs cfg.extraArgs}"
      ];
    };
  };
}
