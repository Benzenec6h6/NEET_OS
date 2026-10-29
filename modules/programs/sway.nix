{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.sway;
in {
  options.programs.sway = {
    enable = mkEnableOption "Sway Wayland compositor";

    configFile = mkOption {
      type = types.path;
      description = "Sway 設定ファイル (sway.conf) のパス";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [pkgs.sway];

    services.seatd.enable = mkDefault true;

    # 指定された設定ファイルを /etc/sway/config として配置
    environment.etc."sway/config".source = cfg.configFile;

    # VMでのマウス消失を防ぐ環境変数
    environment.sessionVariables = {
      WLR_NO_HARDWARE_CURSORS = "1";
    };

    # DMが探索する Wayland セッションメタデータ
    environment.etc."wayland-sessions/sway.desktop".text = ''
      [Desktop Entry]
      Name=Sway
      Comment=An i3-compatible Wayland compositor
      Exec=${pkgs.sway}/bin/sway
      Type=Application
    '';
  };
}
