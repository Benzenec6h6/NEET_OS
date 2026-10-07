{
  config,
  lib,
  ...
}: let
  cfg = config.impermanence;
  fileSystems = config.boot.fileSystems;

  rootFs = fileSystems."/" or {};
  rootFsType = rootFs.fsType or "";

  # 永続化用ストレージ（缶）のマウント定義
  persistFs = fileSystems.${cfg.persistPath} or null;

  # リセット対象として指定されているマウント一覧
  resetMounts = lib.filterAttrs (n: fs: fs.resetOnBoot) fileSystems;

  # directories 内の重複（同じパスを2回書いた）
  # ※ 旧 assertion 6 は「自分が注入した boot.fileSystems」を見ていたため
  #   directories が空でない限り必ず失敗していた。削除し、検査対象を cfg 側に移す。
  duplicateDirs = lib.filter (d: lib.count (x: x == d) cfg.directories > 1) (lib.unique cfg.directories);

  # 絶対パスでないもの
  relativeDirs = lib.filter (d: !(lib.hasPrefix "/" d)) cfg.directories;

  # persistPath 配下を指しているもの（bind元と bind先が循環する）
  underPersist = lib.filter (d: d == cfg.persistPath || lib.hasPrefix "${cfg.persistPath}/" d) cfg.directories;
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
      example = ["/var/log" "/var/lib/iwd"];
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

      # 6. directories 自体の整合性（cfg だけを見る。注入結果は見ない）
      {
        assertion = duplicateDirs == [];
        message = "Impermanence: directories に重複があります: ${toString duplicateDirs}";
      }
      {
        assertion = relativeDirs == [];
        message = "Impermanence: directories は絶対パスで指定してください: ${toString relativeDirs}";
      }
      {
        assertion = underPersist == [];
        message = "Impermanence: ${cfg.persistPath} 配下は directories に指定できません: ${toString underPersist}";
      }

      # ★ 追加 7: ルートがリセット対象なのに、/nix の独立マウントがない構成を弾く
      {
        assertion = !(rootFs.resetOnBoot or false) || (fileSystems ? "/nix" || fileSystems ? "/nix/store");
        message = "Impermanence: ルートが resetOnBoot = true ですが、/nix または /nix/store のマウント定義がありません！Nix Store が退避・消去されてしまいます。";
      }

      # ★ 追加 8: /nix 自体がリセット対象になっていないこと
      {
        assertion = !((fileSystems."/nix" or {}).resetOnBoot or false) && !((fileSystems."/nix/store" or {}).resetOnBoot or false);
        message = "Impermanence: /nix または /nix/store に resetOnBoot = true が設定されています！OSが破壊されます。";
      }

      # ★ 追加 9: resetOnBoot = true をつけたマウントはすべて neededForBoot = true が必須
      # (理由: Btrfs リセットは Stage 1 の early-init で実行するため)
      {
        assertion = lib.all (fs: !fs.resetOnBoot || fs.neededForBoot) (lib.attrValues fileSystems);
        message = "Impermanence: resetOnBoot = true を設定したファイルシステムは、すべて neededForBoot = true である必要があります。";
      }
    ];

    # 永続化パスを boot.fileSystems の bind マウントに変換して注入する。
    # ユーザーが同じキーに device を定義していれば、モジュールシステムが
    # 「複数箇所で定義されている」エラーを出すので、別途の衝突検知は不要。
    boot.fileSystems = lib.genAttrs cfg.directories (dir: {
      device = "${cfg.persistPath}${dir}";
      fsType = "none";
      options = ["bind"];
      neededForBoot = false; # Stage 2 でマウント
    });
  };
}
