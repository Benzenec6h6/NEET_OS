{
  config,
  lib,
  ...
}:
with lib; let
  cfg = config.neet.windowManager;
in {
  imports = [
    ./hyprland.nix
    ./sway.nix
  ];

  options.neet.windowManager = {
    # 各WMモジュールが自分の有効化時に mkIf で定義し、list の結合で集まる
    active = mkOption {
      type = types.listOf types.str;
      default = [];
      internal = true;
      description = "有効化されているWMの名前一覧 (各WMモジュールが自己申告する)";
    };
  };

  # 方針: X11セッションは非サポート。必要ならXWaylandを使うこと。
  config = mkIf (cfg.active != []) {
    services.seatd.enable = mkDefault true;
    environment.variables.WLR_NO_HARDWARE_CURSORS = "1";
  };
}
