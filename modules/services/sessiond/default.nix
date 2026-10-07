{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.sessiond;

  format = pkgs.formats.toml {};
  configFile = format.generate "sessiond.toml" cfg.settings;
in {
  options.services.sessiond = {
    enable = lib.mkEnableOption "sessiond daemon";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.sessiond;
      defaultText = lib.literalExpression "pkgs.sessiond";
      description = "The package to use for sessiond.";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable debug logging.";
    };

    settings = lib.mkOption {
      type = format.type;
      default = {};
      description = "sessiond configuration.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # D-Bus ポリシーの登録
    services.dbus.enable = true;
    services.dbus.packages = [cfg.package];

    # 電源管理コマンド (NEET_OS の system-init に向ける)
    services.sessiond.settings.power = {
      reboot = lib.mkDefault ["/bin/reboot"];
      poweroff = lib.mkDefault ["/bin/poweroff"];
    };

    # s6-rc サービス定義
    system.s6-rc.services.sessiond = {
      type = "longrun";
      dependencies = ["dbus"];

      # ★ s6 に通知を受け取る準備をさせる (通常 fd 3 を使う)
      notification-fd = 3;

      run = ''
        #!/bin/sh
        export LOG_LEVEL="${
          if cfg.debug
          then "debug"
          else "info"
        }"

        # ★ s6-notify-fd-from-socket を挟んで起動
        # (pkgs.s6 の中に含まれています)
        exec ${pkgs.s6}/bin/s6-notify-fd-from-socket -3 3 \
          ${lib.getExe' cfg.package "sessiond"} --config ${configFile} --log-target stderr
      '';
    };
  };
}
