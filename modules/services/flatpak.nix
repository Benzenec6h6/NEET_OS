{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.flatpak;

  # 同期用のシェルスクリプト
  syncScript = pkgs.writeShellScript "flatpak-managed-sync" ''
    set -e

    # 1. Flathub リポジトリの登録確認
    ${cfg.package}/bin/flatpak remote-add --system --if-not-exists flathub \
      https://dl.flathub.org/repo/flathub.flatpakrepo || true

    # 2. 宣言されたパッケージのインストール / アップデート
    ${optionalString (cfg.packages != []) ''
      echo "neet-flatpak: syncing declared packages..."
      for app in ${escapeShellArgs cfg.packages}; do
        echo "neet-flatpak: ensuring $app..."
        ${cfg.package}/bin/flatpak install --system -y --noninteractive --or-update flathub "$app" || {
          echo "neet-flatpak: warning: failed to install/update $app (network down?)"
        }
      done
    ''}

    # 3. 宣言から消えたパッケージの自動削除 (prune が有効な場合)
    ${optionalString cfg.prune ''
      echo "neet-flatpak: checking for undeclared packages to prune..."
      INSTALLED=$(${cfg.package}/bin/flatpak list --system --app --columns=application)
      DECLARED=(${escapeShellArgs cfg.packages})

      for inst in $INSTALLED; do
        KEEP=0
        for dec in "''${DECLARED[@]}"; do
          if [ "$inst" = "$dec" ]; then
            KEEP=1
            break
          fi
        done

        if [ "$KEEP" -eq 0 ]; then
          echo "neet-flatpak: uninstalling undeclared package: $inst"
          ${cfg.package}/bin/flatpak uninstall --system -y --noninteractive "$inst" || true
        fi
      done
    ''}
  '';
in {
  options.services.flatpak = {
    enable = mkEnableOption "Flatpak application sandboxing and distribution framework";

    package = mkOption {
      type = types.package;
      default = pkgs.flatpak;
      description = "使用する flatpak パッケージ";
    };

    packages = mkOption {
      type = types.listOf types.str;
      default = [];
      example = [
        "com.usebottles.bottles"
        "com.spotify.Client"
        "com.discordapp.Discord"
      ];
      description = "システムに宣言的にインストール・維持する Flatpak アプリの App ID リスト";
    };

    prune = mkOption {
      type = types.bool;
      default = false;
      description = ''
        packages リストに存在しないシステム Flatpak アプリを自動的にアンインストールするかどうか。
        手動で flatpak install したアプリも消えるため、完全に宣言的管理にしたい場合のみ true にしてください。
      '';
    };

    update = {
      enable = mkOption {
        type = types.bool;
        default = true;
        description = "fcron によるシステム Flatpak アプリの定期自動更新を有効にするか";
      };

      interval = mkOption {
        type = types.str;
        default = "@daily";
        description = "更新チェックの間隔 (fcron 形式)";
      };
    };
  };

  config = mkIf cfg.enable {
    # パッケージ本体とサンドボックス基盤
    environment.systemPackages = [
      cfg.package
      pkgs.bubblewrap
      pkgs.xdg-user-dirs
    ];

    # D-Bus サービスの登録 (org.freedesktop.Flatpak)
    services.dbus.packages = [cfg.package];

    # システムステートディレクトリ
    system.stateDirectories = [
      {
        path = "/var/lib/flatpak";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # XDG_DATA_DIRS の統合 (アプリの .desktop / アイコンを認識)
    environment.etc."profile.d/flatpak.sh".text = ''
      if [ -z "$XDG_DATA_DIRS" ]; then
        XDG_DATA_DIRS="/usr/local/share:/usr/share"
      fi
      export XDG_DATA_DIRS="/var/lib/flatpak/exports/share:$HOME/.local/share/flatpak/exports/share:$XDG_DATA_DIRS"
    '';

    # 定期更新 (fcron 連携)
    services.fcron = mkIf cfg.update.enable {
      enable = mkDefault true;
      systab = [
        "&bootrun ${cfg.update.interval} root ${cfg.package}/bin/flatpak update -y --noninteractive"
      ];
    };

    # 宣言的パッケージ同期 (s6-rc oneshot サービス)
    # 起動時（または s6-rc start）に Flathub 登録と宣言パッケージの同期を実行
    system.s6-rc.services.flatpak-managed-sync = {
      type = "oneshot";
      format = "sh";
      dependencies = ["dbus"];
      autoStart = true;
      up = "${syncScript}";
    };
  };
}
