{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.networking;
in {
  options.networking = {
    upInterfaces = mkOption {
      type = types.listOf types.str;
      default = ["lo"];
      description = "起動時に自動的に UP にするネットワークインターフェース名のリスト";
      example = ["lo" "eth0"];
    };

    dhcpInterfaces = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "udhcpc を有効化するインターフェースのリスト";
      example = ["eth0"];
    };
  };

  config = {
    environment.etc."network/up_interfaces".text =
      concatStringsSep "\n" cfg.upInterfaces + "\n";

    # udhcpc サービスの自動生成
    system.s6-rc.services = listToAttrs (map (iface: {
        name = "udhcpc-${iface}";
        value = {
          type = "longrun";
          # mdevd が有効なら coldplug 完了後に実行する
          dependencies = optional config.services.mdevd.enable "mdevd-coldplug";
          run = ''
            #!/bin/execlineb -P
            exec udhcpc -f -i ${iface}
          '';
        };
      })
      cfg.dhcpInterfaces);
  };
}
