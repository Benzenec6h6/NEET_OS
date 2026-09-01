{lib, ...}: let
  # 個別のマウントエントリの型定義
  mountOpts = {name, ...}: {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = name;
        description = "マウント先のパス";
      };
      device = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "デバイスパス、または tmpfs / proc 等の識別子";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "auto";
        description = "ファイルシステムの種類";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["defaults"];
        description = "マウントオプション（fstab形式）";
      };
      alreadyMounted = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Stage 1 等で既にマウント済みであり、Stage 2 (system-init) での
          マウント処理をスキップすべきかどうかのフラグ (原則2)。
          fstab などの宣言出力には含まれます。
        '';
      };
      dump = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
      pass = lib.mkOption {
        type = lib.types.int;
        default = 0;
      };
    };
  };
in {
  options = {
    boot = {
      # 原則1: Stage 1 (initrd) 専用のマウント定義
      stage1.fileSystems = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule mountOpts);
        default = {};
        description = "Stage 1 (initrd) で switch_root するために必要な最小限のマウント";
      };

      # 原則1: Stage 2 (system-init) 専用のマウント定義
      stage2.fileSystems = lib.mkOption {
        type = lib.types.attrsOf (lib.types.submodule mountOpts);
        default = {};
        description = "Stage 2 (system-init) で実行時環境を仕上げるための仮想FSなどのマウント";
      };
    };
  };
}
