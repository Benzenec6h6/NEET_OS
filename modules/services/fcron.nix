{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.fcron;

  # /etc/fcron.conf の生成
  fcronConf = pkgs.writeText "fcron.conf" ''
    # スプール・FIFO・アクセス制御ファイルのパス
    fcrontabs = /var/spool/fcron
    fifofile  = /run/fcron/fcron.fifo
    fcronallow = /etc/fcron.allow
    fcrondeny  = /etc/fcron.deny

    # 実行シェル
    shell = /bin/sh

    # メール送信プログラム（無効化または任意の sendmail）
    sendmail = ${pkgs.coreutils}/bin/true

    # 任意の設定追加
    ${cfg.extraConfig}
  '';

  # システム全体の定期タスク (systab)
  systabFile = pkgs.writeText "fcron.systab" ''
    # NEET_OS System Crontab (fcron)
    # 構文: 分 時 日 月 曜日 コマンド または &bootrun @daily コマンド
    ${concatStringsSep "\n" cfg.systab}
  '';
in {
  options.services.fcron = {
    enable = mkEnableOption "fcron periodic command scheduler";

    package = mkOption {
      type = types.package;
      default = pkgs.fcron;
      description = "使用する fcron パッケージ";
    };

    systab = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [
        "&bootrun 0 3 * * * root /run/current-system/bin/rebuild.sh"
        "&bootrun @daily root fstrim -av"
      ];
      description = "システム全体 (root権限) で定期実行するタスクの一覧";
    };

    allow = mkOption {
      type = types.listOf types.str;
      default = ["root"];
      description = "fcrontab の使用を許可するユーザーの一覧 (/etc/fcron.allow)";
    };

    deny = mkOption {
      type = types.listOf types.str;
      default = ["all"];
      description = "fcrontab の使用を拒否するユーザーの一覧 (/etc/fcron.deny)";
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      description = "fcron.conf に追加する任意の設定ディレクティブ";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "fcron デーモンに渡す追加のコマンドライン引数";
    };
  };

  config = mkIf cfg.enable {
    # 1. fcron 専用のシステムユーザー / グループ
    # ※ fcron はデーモン自身とスプールがこのユーザー・グループに属していることを厳密に要求します
    neet.users.fcron = {
      uid = mkDefault 982;
      gid = mkDefault 982;
      description = "fcron daemon user";
      home = "/var/spool/fcron";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = false;
      createRuntimeDir = false;
    };

    neet.gids.fcron = mkDefault 982;

    # 2. ステート・ランタイムディレクトリの定義
    system.stateDirectories = [
      {
        path = "/var/spool/fcron";
        mode = "0770";
        user = "fcron";
        group = "fcron";
      }
      {
        path = "/run/fcron";
        mode = "0755";
        user = "fcron";
        group = "fcron";
      }
    ];

    # 3. 設定ファイル・アクセス制御ファイルの配置
    environment.etc."fcron.conf".source = fcronConf;
    environment.etc."fcron.allow".text = concatStringsSep "\n" cfg.allow + "\n";
    environment.etc."fcron.deny".text = concatStringsSep "\n" cfg.deny + "\n";

    # 管理・操作用コマンドを PATH に含める
    environment.systemPackages = [cfg.package];

    # 4. 一般ユーザーが fcrontab / fcrondyn を実行可能にするための setuid ラッパー
    neet.security.wrappers = {
      fcrontab = {
        source = "${cfg.package}/bin/fcrontab";
        setuid = true;
        setgid = true;
        owner = "fcron";
        group = "fcron";
      };
      fcrondyn = {
        source = "${cfg.package}/bin/fcrondyn";
        setuid = true;
        setgid = true;
        owner = "fcron";
        group = "fcron";
      };
      fcronsighup = {
        source = "${cfg.package}/bin/fcronsighup";
        setuid = true;
        setgid = true;
        owner = "fcron";
        group = "fcron";
      };
    };

    # 5. s6-rc サービス定義
    system.s6-rc.services.fcron = {
      type = "longrun";
      autoStart = true;

      # 起動スクリプト:
      # - 起動直前に systabFile を fcron 形式でスプールに反映 (fcrontab -u systab)
      # - --foreground: s6-rc による監視のためフォアグラウンド実行
      # - -c: 設定ファイル指定
      run = ''
        #!${pkgs.runtimeShell}
        set -e

        # システムタスク (systab) の同期
        ${cfg.package}/bin/fcrontab -c /etc/fcron.conf -u systab ${systabFile} 2>/dev/null || true

        # デーモン起動
        exec ${cfg.package}/bin/fcron --foreground -c /etc/fcron.conf ${escapeShellArgs cfg.extraArgs}
      '';

      # s6-log によるロギング自動生成
      log.enable = true;

      # syslog や chrony (時刻同期) があれば時刻が合ってから起動するのが望ましい
      dependencies =
        optional (config.services.chrony.enable or false) "chronyd"
        ++ optional (config.services.syslog.enable or false) "syslogd";
    };
  };
}
