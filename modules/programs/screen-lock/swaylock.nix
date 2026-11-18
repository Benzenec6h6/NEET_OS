{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.programs.screen-lock.swaylock;

  # configFile や extraConfig が指定された場合、それを指す Nix store パス
  customConfigFile =
    if cfg.configFile != null
    then cfg.configFile
    else if cfg.extraConfig != ""
    then pkgs.writeText "swaylock-config" cfg.extraConfig
    else null;

  # 設定ファイルが指定されている場合は、デフォルトで --config /etc/swaylock/config を渡すラッパーを作成
  wrappedSwaylock = pkgs.symlinkJoin {
    name = "swaylock-wrapped";
    paths = [cfg.package];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/swaylock \
        --add-flags "--config /etc/swaylock/config"
    '';
  };
in {
  options.neet.programs.screen-lock.swaylock = {
    enable = mkEnableOption "swaylock (Wayland screen locker)";

    package = mkOption {
      type = types.package;
      default = pkgs.swaylock-effects;
      description = "使用する swaylock パッケージ";
    };

    configFile = mkOption {
      type = types.nullOr types.path;
      default = null;
      example = literalExpression "./swaylock.config";
      description = "外部の config ファイルパス（指定時は /etc/swaylock/config に配置されます）";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "インラインで設定を書く場合の内容";
    };
  };

  config = mkIf cfg.enable {
    # 設定が指定されている場合はラッパー版を、指定がなければ生バイナリを提供
    # （ユーザー自身の ~/.config/swaylock/config を優先させたい場合はラッパーなしで素直に動きます）
    environment.systemPackages = [
      (
        if customConfigFile != null
        then wrappedSwaylock
        else cfg.package
      )
    ];

    # PAM 認証 (/etc/pam.d/swaylock)
    neet.security.pam.services.swaylock = {};

    # /etc/swaylock/config の配置
    environment.etc."swaylock/config" = mkIf (customConfigFile != null) {
      source = customConfigFile;
    };
  };
}
