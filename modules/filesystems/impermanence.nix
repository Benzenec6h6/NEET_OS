{
  config,
  lib,
  ...
}: let
  cfg = config.impermanence;
  fileSystems = config.boot.fileSystems;

  # 1. ルートと永続ストレージのマウント情報
  rootFs = fileSystems."/" or {};
  rootFsType = rootFs.fsType or "";
  persistFs = fileSystems.${cfg.persistPath} or null;
  resetMounts = lib.filterAttrs (n: fs: fs.resetOnBoot) fileSystems;

  # 2. 文字列でも submodule でも同じ形式 ({ path, user, group, mode }) に正規化
  normalizedDirs =
    map (
      d:
        if builtins.isString d
        then {
          path = d;
          user = "root";
          group = "root";
          mode = "0755";
        }
        else d
    )
    cfg.directories;

  # パスだけの文字列リスト (例: ["/var/log", "/home/neet"])
  dirPaths = map (d: d.path) normalizedDirs;

  # 3. ★ アサーション用の検査ロジック（cfg.directories ではなく dirPaths を検査する）
  duplicateDirs = lib.filter (d: lib.count (x: x == d) dirPaths > 1) (lib.unique dirPaths);
  relativeDirs = lib.filter (d: !(lib.hasPrefix "/" d)) dirPaths;
  underPersist = lib.filter (d: d == cfg.persistPath || lib.hasPrefix "${cfg.persistPath}/" d) dirPaths;
in {
  options.impermanence = {
    enable = lib.mkEnableOption "Impermanence (stateless root)";

    persistPath = lib.mkOption {
      type = lib.types.str;
      default = "/persist";
      description = "永続化データを保存するストレージのマウント先";
    };

    directories = lib.mkOption {
      type = lib.types.listOf (lib.types.either lib.types.str (lib.types.submodule {
        options = {
          path = lib.mkOption {
            type = lib.types.str;
            description = "永続化するパス";
          };
          user = lib.mkOption {
            type = lib.types.str;
            default = "root";
            description = "所有ユーザー";
          };
          group = lib.mkOption {
            type = lib.types.str;
            default = "root";
            description = "所有グループ";
          };
          mode = lib.mkOption {
            type = lib.types.str;
            default = "0755";
            description = "パーミッション（8進数文字列 例: '0700', '0755'）";
          };
        };
      }));
      default = [];
      example = [
        "/var/log"
        {
          path = "/home/neet";
          user = "neet";
          group = "users";
          mode = "0700";
        }
      ];
      description = "永続化するディレクトリ群（bind mount され、所有権も自動設定されます）";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. パス一覧 (dirPaths) を使って bind マウントを定義
    boot.fileSystems = lib.genAttrs dirPaths (dir: {
      device = "${cfg.persistPath}${dir}";
      fsType = "none";
      options = ["bind"];
      neededForBoot = false;
    });

    # 2. 実体 (/persist/...) と マウント先 (/...) の両方を system.stateDirectories に注入
    system.stateDirectories =
      lib.concatMap (d: [
        {
          path = "${cfg.persistPath}${d.path}";
          inherit (d) mode user group;
        }
        {
          path = d.path;
          inherit (d) mode user group;
        }
      ])
      normalizedDirs;

    # 3. 整合性チェック（アサーション）
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

      # 3. 永続化ストレージ自身がリセット対象になっていないこと
      {
        assertion = !(builtins.hasAttr cfg.persistPath resetMounts);
        message = "Impermanence: 永続化ストレージ (${cfg.persistPath}) に resetOnBoot = true が設定されています！データが消去されてしまいます。";
      }

      # 4. ルートが tmpfs なのに /persist の実ストレージ定義が抜けていないか
      {
        assertion = rootFsType != "tmpfs" || persistFs != null;
        message = "Impermanence: ルートが tmpfs ですが、${cfg.persistPath} に実ディスクが割り当てられていません。";
      }

      # 5. /persist は起動初期に必須
      {
        assertion = persistFs == null || (persistFs.neededForBoot or false);
        message = "Impermanence: ${cfg.persistPath} には neededForBoot = true が必要です。";
      }

      # 6. directories 自体の整合性（dirPaths でチェック）
      {
        assertion = duplicateDirs == [];
        message = "Impermanence: directories に重複したパスがあります: ${toString duplicateDirs}";
      }
      {
        assertion = relativeDirs == [];
        message = "Impermanence: directories は絶対パスで指定してください: ${toString relativeDirs}";
      }
      {
        assertion = underPersist == [];
        message = "Impermanence: ${cfg.persistPath} 配下のパスは directories に指定できません: ${toString underPersist}";
      }

      # 7. ルートがリセット対象なのに、/nix の独立マウントがない構成を弾く
      {
        assertion = !(rootFs.resetOnBoot or false) || (fileSystems ? "/nix" || fileSystems ? "/nix/store");
        message = "Impermanence: ルートが resetOnBoot = true ですが、/nix または /nix/store のマウント定義がありません！Nix Store が退避・消去されてしまいます。";
      }

      # 8. /nix 自体がリセット対象になっていないこと
      {
        assertion = !((fileSystems."/nix" or {}).resetOnBoot or false) && !((fileSystems."/nix/store" or {}).resetOnBoot or false);
        message = "Impermanence: /nix または /nix/store に resetOnBoot = true が設定されています！OSが破壊されます。";
      }

      # 9. resetOnBoot = true をつけたマウントはすべて neededForBoot = true が必須
      {
        assertion = lib.all (fs: !fs.resetOnBoot || fs.neededForBoot) (lib.attrValues fileSystems);
        message = "Impermanence: resetOnBoot = true を設定したファイルシステムは、すべて neededForBoot = true である必要があります。";
      }
    ];
  };
}
