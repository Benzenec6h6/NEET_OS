{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.neet-helper;
  inieet = pkgs.callPackage ../../pkgs/inieet {};

  adminDir = "/run/neet-admin";
  socketPath = "${adminDir}/sock";

  # サーバ側はラッパーなしの素のバイナリを使う
  neetBin = "${inieet.neetHelper}/bin/neet";

  wrappedNeet = pkgs.symlinkJoin {
    name = "neet-wrapped";
    paths = [inieet.neetHelper];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/neet \
        --set NEET_ADMIN_SOCK "${socketPath}" \
        --set NEET_S6_SUDO "${pkgs.s6}/bin/s6-sudo" \
        --set NEET_ROM "${pkgs.rom}/bin/rom" \
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
    environment.systemPackages = [wrappedNeet];

    # ディレクトリ権限が第一の関門 (グループ外は socket に到達できない)
    system.stateDirectories = [
      {
        path = adminDir;
        mode = "0750";
        user = "root";
        group = cfg.allowedGroup;
      }
    ];

    system.s6-rc.services.neet-admin-server = {
      type = "longrun";
      autoStart = true;
      run = ''
        #!/bin/sh
        exec 2>&1

        export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/run/current-system/bin:/bin:/sbin"
        export NIX_REMOTE="daemon"
        export HOME="/root"
        # neet priv 側の二重チェック用
        export NEET_ALLOWED_GROUP="${cfg.allowedGroup}"

        rm -f ${socketPath}

        # 接続ごとに s6-sudod が `neet priv <クライアント引数...>` を実行する
        exec ${pkgs.s6}/bin/s6-ipcserver -a 0666 ${socketPath} \
          ${pkgs.s6}/bin/s6-sudod ${neetBin} priv
      '';
    };
  };
}
