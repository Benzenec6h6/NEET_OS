{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.neet-helper;
  inieet = pkgs.callPackage ../../pkgs/inieet {};

  socketPath = "/run/neet-admin.sock";

  # 環境変数を注入した neet コマンド
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
    # 1. ラップされた CLI を一般 PATH に追加
    environment.systemPackages = [
      wrappedNeet
      pkgs.s6 # s6-sudo コマンドを使うため
    ];

    # 2. root 権限で動く s6-sudod サービスを定義！
    # wheel グループのユーザーだけが /run/neet-admin.sock に接続できる
    system.s6-rc.services.neet-admin-server = {
      type = "longrun";
      autoStart = true;
      run = ''
        #!/bin/execlineb -P
        fdmove -c 2 1
        s6-ipcserver -m 0660 -g ${cfg.allowedGroup} ${socketPath}
        s6-sudod
      '';
    };
  };
}
