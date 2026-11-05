{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.chrony;

  # 設定ファイルの生成
  chronyConf = pkgs.writeText "chrony.conf" ''
    # NTP サーバー設定 (iburst: 起動時に素早く同期)
    ${concatMapStringsSep "\n" (server: "pool ${server} iburst") cfg.servers}

    # クロックのズレ(ドリフト)記録ファイル
    driftfile /var/lib/chrony/chrony.drift

    # 起動直後の大幅なズレをステップ調整する(1秒以上のズレを最初の3回の更新で補正)
    makestep 1.0 3

    # システムクロックの補正を Linux カーネル経由で RTC (ハードウェア時計) に書き戻す
    rtcsync

    # chronyc コマンド用ソケットなどの出力先
    dumpdir /run/chrony

    # 追加の設定
    ${cfg.extraConfig}
  '';
in {
  options.services.chrony = {
    enable = mkEnableOption "chrony NTP daemon";

    package = mkOption {
      type = types.package;
      default = pkgs.chrony;
      description = "使用する chrony パッケージ";
    };

    servers = mkOption {
      type = types.listOf types.str;
      default = [
        "pool.ntp.org"
      ];
      description = "同期先 NTP サーバーまたはプールの一覧";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "chrony.conf に追加する任意の設定ディレクティブ";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "chronyd に渡す追加のコマンドライン引数";
    };
  };

  config = mkIf cfg.enable {
    # 1. 特権分離用の専用ユーザー / グループ
    neet.users.chrony = {
      uid = mkDefault 981;
      gid = mkDefault 981;
      description = "chrony daemon user";
      home = "/var/lib/chrony";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = false;
      createRuntimeDir = false;
    };

    neet.gids.chrony = mkDefault 981;

    # 2. neet-activate 用のステート・ランタイムディレクトリ定義
    system.stateDirectories = [
      {
        path = "/var/lib/chrony";
        mode = "0750";
        user = "chrony";
        group = "chrony";
      }
      {
        path = "/run/chrony";
        mode = "0750";
        user = "chrony";
        group = "chrony";
      }
    ];

    # 3. 設定ファイルの配置 (/etc/chrony.conf)
    environment.etc."chrony.conf".source = chronyConf;

    # 操作・状態確認用コマンド (chronyc) をシステムパスに含める
    environment.systemPackages = [cfg.package];

    # 4. s6-rc サービス定義
    system.s6-rc.services.chronyd = {
      type = "longrun";
      autoStart = true;

      # build-source.nix の仕様に合わせ shebang 付きで記述
      # -d: フォアグラウンド実行 (s6-rc 必須)
      # -s: 起動時に RTC から時刻を取得して初期化
      # -u: バインド完了後に chrony ユーザーへ権限降格
      # -f: 設定ファイル指定
      run = ''
        #!${pkgs.runtimeShell}
        exec ${cfg.package}/bin/chronyd -d -s -u chrony -f /etc/chrony.conf ${escapeShellArgs cfg.extraArgs}
      '';

      # NEET_OS 組み込みの s6-log 自動生成機構を活用
      log.enable = true;

      # 名前解決/ネットワークが初期化されてから起動
      # ※ お使いのネットワークサービス名（dhcpcd や resolvconf）に合わせて調整可能
      dependencies = optional (config.services.dhcpcd.enable or false) "dhcpcd";
    };
  };
}
