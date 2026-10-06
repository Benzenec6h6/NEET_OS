{
  config,
  lib,
  ...
}: let
  cfg = config.impermanence;
  fileSystems = config.boot.fileSystems;

  rootFs = fileSystems."/" or null;
  rootFsType = rootFs.fsType or "";

  # 永続化用ストレージ（缶）のマウント定義
  persistFs = fileSystems."${cfg.persistPath}" or null;

  # リセット対象として指定されているマウント一覧
  resetMounts = lib.filterAttrs (n: fs: fs.resetOnBoot) fileSystems;

  # 既存マウントと衝突しているディレクトリの検出
  conflictingDirs = lib.filter (dir: builtins.hasAttr dir fileSystems) cfg.directories;
in {
  options.impermanence = {
    enable = lib.mkEnableOption "Impermanence (stateless root)";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "永続化データを保存するストレージのマウント先";
    };

    directories = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      example = ["/var/log" "/etc/machine-id"];
      description = "永続化するディレクトリ群（bind mount されます）";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      # 1. ルートが tmpfs か btrfs であること
      {
        assertion = builtins.elem rootFsType ["tmpfs" "btrfs"];
        message = "Impermanence: ルート (/) は tmpfs または btrfs である必要があります。(現在: ${rootFsType})";
      }

      # 2. btrfs の場合、ルートが resetOnBoot になっていること
      {
        assertion = rootFsType != "btrfs" || (rootFs.resetOnBoot or false);
        message = "Impermanence: ルートが btrfs の場合、boot.fileSystems.\"/\".resetOnBoot = true が必要です。";
      }

      # 3. 事故防止: 永続化ストレージ (/persist) 自身がリセット対象になっていないこと
      {
        assertion = !(builtins.hasAttr cfg.persistPath resetMounts);
        message = "Impermanence: 永続化ストレージ (${cfg.persistPath}) に resetOnBoot = true が設定されています！データが消去されてしまいます。";
      }

      # 4. 事故防止: ルートが tmpfs なのに /persist の実ストレージ定義が抜けていないか
      {
        assertion = rootFsType != "tmpfs" || persistFs != null;
        message = "Impermanence: ルートが tmpfs ですが、${cfg.persistPath} に実ディスクが割り当てられていません。";
      }

      # 5. /persist は起動初期に必須
      {
        assertion = persistFs == null || (persistFs.neededForBoot or false);
        message = "Impermanence: ${cfg.persistPath} には neededForBoot = true が必要です。";
      }

      # 6. マウント先が既存のファイルシステムと重複していないこと
      {
        assertion = conflictingDirs == [];
        message = "Impermanence: 以下のパスは既に boot.fileSystems で定義されているため重複できません: ${toString conflictingDirs}";
      }
    ];

    # 永続化パスをすべて boot.fileSystems の bind マウントに自動変換して注入！
    boot.fileSystems = lib.listToAttrs (map (dir: {
        name = dir;
        value = {
          mountPoint = dir;
          device = "${cfg.persistPath}${dir}";
          fsType = "none";
          options = ["bind"];
          neededForBoot = false; # Stage 2 でマウント
        };
      })
      cfg.directories);
  };
}
