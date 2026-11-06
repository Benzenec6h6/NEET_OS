{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.time;
in {
  options.time = {
    timeZone = lib.mkOption {
      type = lib.types.str;
      default = "UTC";
      example = "Asia/Tokyo";
      description = "システム全体のタイムゾーン。";
    };
  };

  config = {
    # 1. /etc/localtime を tzdata の zoneinfo への symlink として配置
    # (etc.nix の mode="symlink" が活きます)
    environment.etc."localtime".source = "${pkgs.tzdata}/share/zoneinfo/${cfg.timeZone}";

    # 2. session-vars.sh 経由で TZ 環境変数を設定
    # tzdata を参照しない簡易コマンド（busybox の date 等）でも正しく機能するようになります
    environment.variables = {
      TZ = cfg.timeZone;
    };
  };
}
