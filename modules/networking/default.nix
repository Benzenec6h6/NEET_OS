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
    environment.etc."hostname".text = mkDefault "${cfg.hostName}\n";

    environment.etc."network/up_interfaces".text =
      concatStringsSep "\n" cfg.upInterfaces + "\n";

    environment.etc."protocols".source = "${pkgs.iana-etc}/etc/protocols";
  };
}
