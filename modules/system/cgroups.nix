{
  config,
  lib,
  ...
}: let
  cgroupOpts = {...}: {
    options = {
      path = lib.mkOption {
        type = lib.types.str;
        example = "/sys/fs/cgroup/system/nix-daemon";
      };
      user = lib.mkOption {
        type = lib.types.str;
        default = "root";
      };
      group = lib.mkOption {
        type = lib.types.str;
        default = "root";
      };
      subtree_control = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
      };
      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.str;
        default = {};
      };
    };
  };
in {
  options.system.cgroups = lib.mkOption {
    type = lib.types.listOf (lib.types.submodule cgroupOpts);
    default = [];
    description = "cgroup v2 nodes to be pre-created by neet-activate";
  };

  config = {
    # /etc/cgroup-plan.json として出力する
    environment.etc."cgroup-plan.json".text = builtins.toJSON config.system.cgroups;

    # OSの基本骨格として最初から作っておくグループ
    system.cgroups = [
      {
        path = "/sys/fs/cgroup/system";
        subtree_control = "+cpu +memory +pids";
      }
      {
        path = "/sys/fs/cgroup/user";
        subtree_control = "+cpu +memory +pids";
      }
      {
        path = "/sys/fs/cgroup/init";
        subtree_control = "+cpu +memory +pids";
      }
    ];
  };
}
