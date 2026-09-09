{lib, ...}: let
  mountOpts = {name, ...}: {
    options = {
      mountPoint = lib.mkOption {
        type = lib.types.str;
        default = name;
      };
      device = lib.mkOption {
        type = lib.types.str;
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
        description = "true の場合、このマウントは Stage 1 (initrd) で行われ、Stage 2 では alreadyMounted として扱われる";
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
  options.boot = {
    # ユーザーが実際に触るのはここだけ
    fileSystems = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule mountOpts);
      default = {};
      description = "実ディスク上のファイルシステム定義（唯一の情報源）";
    };
    # OS側が内部的に必要とする固定の仮想マウント（proc, sysなど）。ユーザーは通常触らない。
    virtualFileSystems = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule mountOpts);
      default = {};
      description = "Stage 2 で常時マウントされる仮想ファイルシステム";
    };
  };
}
