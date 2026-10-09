{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.programs.wireplumber;
  format = pkgs.formats.json {};
in {
  options.programs.wireplumber = {
    enable = lib.mkEnableOption "WirePlumber session manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.wireplumber;
      description = "The package to use for wireplumber.";
    };

    settings = lib.mkOption {
      type = format.type;
      default = {};
      description = "WirePlumber configuration options.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.pipewire.enable = lib.mkDefault true;

    environment.systemPackages = [cfg.package];

    # WirePlumber のカスタム設定をシステム全体に配布
    environment.etc."wireplumber/wireplumber.conf.d/99-neet.conf" = lib.mkIf (cfg.settings != {}) {
      source = format.generate "99-neet.conf" cfg.settings;
    };
  };
}
