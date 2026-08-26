{lib, ...}: let
  specialFSTypes = ["proc" "sysfs" "devtmpfs" "tmpfs" "devpts"];
  pathsNeededForBoot = ["/" "/proc" "/sys" "/dev" "/run" "/tmp" "/var/log"];

  fileSystemOpts = {
    name,
    config,
    ...
  }: {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = name;
      };
      device = lib.mkOption {
        type = lib.types.str;
        # デフォルト値を空文字にしておく
        default = "";
      };
      fsType = lib.mkOption {
        type = lib.types.str;
        default = "auto";
      };
      options = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["defaults"];
      };
      neededForBoot = lib.mkOption {
        type = lib.types.bool;
        default = false;
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

    config = {
      # 条件に config.device を含めず、fsType の判定のみで mkDefault を当てる
      # ユーザーが明示的に device = "/dev/xxx" を書いた場合は mkDefault 側が自動で上書き・譲歩する
      device = lib.mkIf (lib.elem config.fsType specialFSTypes) (lib.mkDefault config.fsType);

      # config.mountPoint ではなく親から渡される name を使って安全に判定
      neededForBoot = lib.mkIf (lib.elem name pathsNeededForBoot) (lib.mkDefault true);
      pass = lib.mkIf (name == "/") (lib.mkDefault 1);
    };
  };
in {
  options = {
    fileSystems = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule fileSystemOpts);
      default = {};
    };
  };
}
