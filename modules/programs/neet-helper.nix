{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.neet-helper;
  inieet = pkgs.callPackage ../../pkgs/inieet {};

  # 専用ディレクトリ配下にソケットを配置
  adminDir = "/run/neet-admin";
  socketPath = "${adminDir}/sock";

  wrappedNeet = pkgs.symlinkJoin {
    name = "neet-wrapped";
    paths = [inieet.neetHelper];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/neet \
        --set NEET_ADMIN_SOCK "${socketPath}" \
        ${optionalString (cfg.flake != null) "--set NEET_FLAKE \"${cfg.flake}\""}
    '';
  };
in {
  options.programs.neet-helper = {
    enable = mkEnableOption "neet-helper (system management CLI with s6-sudo)";

    flake = mkOption {
      type = types.nullOr types.str;
      default = "/etc/neet-os";
      description = "デフォルトで使用する Flake リポジトリのパス";
    };

    allowedGroup = mkOption {
      type = types.str;
      default = "wheel";
      description = "neet-helper によるシステム切り替えを許可するグループ名";
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [
      wrappedNeet
      pkgs.s6
    ];

    # 1. ソケット用ディレクトリを root:wheel (0750) で自動作成
    #    (wheel 以外のユーザーは中に入ることすらできません)
    system.stateDirectories = [
      {
        path = adminDir;
        mode = "0750";
        user = "root";
        group = cfg.allowedGroup;
      }
    ];

    # 2. s6-sudod サービス (オプションを修正)
    system.s6-rc.services.neet-admin-server = {
      type = "longrun";
      autoStart = true;
      run = ''
        #!${pkgs.execline}/bin/execlineb -P
        fdmove -c 2 1
        export PATH /run/wrappers/bin:/run/current-system/bin:/bin:/sbin
        export NIX_REMOTE daemon
        export HOME /root
        s6-ipcserver -a 0666 ${socketPath} s6-sudod
      '';
    };
  };
}
