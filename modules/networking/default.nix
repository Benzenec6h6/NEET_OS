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
      default = ["lo"]; # デフォルトは loopback のみ
      description = "起動時に自動的に UP にするネットワークインターフェース名のリスト";
      example = ["lo" "eth0"];
    };
  };

  config = {
    # /etc/network/up_interfaces にリストを出力
    environment.etc."network/up_interfaces".text =
      concatStringsSep "\n" cfg.upInterfaces + "\n";
  };
}
