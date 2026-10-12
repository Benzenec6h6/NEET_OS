{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.networking;
in {
  imports = [
    ./resolvconf.nix
  ];

  options.networking = {
    hostName = mkOption {
      type = types.str;
      default = "neet";
      description = "システムのホスト名";
    };

    upInterfaces = mkOption {
      type = types.listOf types.str;
      default = ["lo"];
      description = "起動時に自動的に UP にするネットワークインターフェース名のリスト";
      example = ["lo" "eth0"];
    };
  };

  config = {
    # 1. /etc/hostname
    environment.etc."hostname".text = mkDefault "${cfg.hostName}\n";

    # 2. /etc/hosts (名前解決の警告や SSH のタイムアウトを防ぐため追加)
    environment.etc."hosts".text = mkDefault ''
      127.0.0.1 localhost ${cfg.hostName}
      ::1       localhost ${cfg.hostName}
    '';

    environment.etc."network/up_interfaces".text =
      concatStringsSep "\n" cfg.upInterfaces + "\n";

    environment.etc."protocols".source = "${pkgs.iana-etc}/etc/protocols";

    # 3. s6-rc: カーネルにホスト名を反映する oneshot サービス
    system.s6-rc.services.hostname = {
      type = "oneshot";
      # /proc/sys/kernel/hostname に直接書き込んでカーネルのホスト名を更新
      up = ''
        printf '%s' "${cfg.hostName}" > /proc/sys/kernel/hostname
      '';
      down = "";
    };
  };
}
