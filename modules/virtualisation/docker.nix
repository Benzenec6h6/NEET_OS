{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.virtualisation.docker;

  # /etc/docker/daemon.json の生成
  # 非 systemd (s6-rc) 環境で必須の設定を固める
  daemonConfig =
    {
      # 1. cgroupfs ドライバーの明示
      "exec-opts" = ["native.cgroupdriver=cgroupfs"];

      # 2. cgroup v2 の親ノードを NEET_OS の階層に合わせる
      "cgroup-parent" = "/docker";

      # 3. journald ではなく json-file ロガーを強制 (journald が無いため必須)
      "log-driver" = "json-file";
      "log-opts" = {
        "max-size" = "10m";
        "max-file" = "3";
      };

      # 4. ストレージドライバー (Linux カーネル標準の overlay2)
      "storage-driver" = "overlay2";
    }
    // cfg.extraDaemonConfig;

  daemonJson = pkgs.writeText "docker-daemon.json" (builtins.toJSON daemonConfig);
in {
  options.virtualisation.docker = {
    enable = mkEnableOption "Docker application container engine";

    package = mkOption {
      type = types.package;
      default = pkgs.docker;
      description = "使用する Docker パッケージ (dockerd, docker CLI 含む)";
    };

    extraDaemonConfig = mkOption {
      type = types.attrsOf types.anything;
      default = {};
      example = {
        "bip" = "172.20.0.1/16";
        "insecure-registries" = ["myregistry.local:5000"];
      };
      description = "/etc/docker/daemon.json にマージする追加の設定";
    };
  };

  config = mkIf cfg.enable {
    # 1. Docker CLI コマンドの導入
    environment.systemPackages = [cfg.package];

    # 2. docker グループの作成 (所属ユーザーが sudo なしで docker を叩けるようにする)
    neet.gids.docker = mkDefault 995;

    # 3. cgroups.nix との連携
    # NEET_OS の cgroup-plan.json に /sys/fs/cgroup/docker を登録し、
    # 必要なコントローラを事前に許可しておく
    system.cgroups = [
      {
        path = "/sys/fs/cgroup/docker";
        subtree_control = "+cpu +memory +pids +io";
      }
    ];

    # 4. ステート・ランタイムディレクトリの確保
    system.stateDirectories = [
      {
        path = "/var/lib/docker";
        mode = "0710";
        user = "root";
        group = "root";
      }
      {
        path = "/run/docker";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # 5. 設定ファイル /etc/docker/daemon.json の配置
    environment.etc."docker/daemon.json".source = daemonJson;

    # 6. s6-rc サービス定義 (dockerd)
    system.s6-rc.services.dockerd = {
      type = "longrun";
      autoStart = true;

      # syslog や時刻同期があればそれに依存 (ネットワーク起動後が望ましい)
      dependencies = optional config.services.syslog.enable "syslog";

      # dockerd 本体の起動
      # Nixpkgs の docker パッケージは containerd や runc へのパス解決を内包しています
      run = ''
        #!${pkgs.runtimeShell}
        exec ${cfg.package}/bin/dockerd \
          --config-file /etc/docker/daemon.json \
          --group docker
      '';

      # s6-log によるログ収集
      log.enable = true;
    };
  };
}
