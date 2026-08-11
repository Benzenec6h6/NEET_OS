{
  pkgs,
  lib,
  config,
  ...
}: {
  options.system.build = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    internal = true;
  };

  config = let
    stage2Init = pkgs.replaceVarsWith {
      src = ./stage2.sh;
      replacements = {
        systemPath = config.system.path;
        s6 = pkgs.s6;
        # activationScriptはファイルパスとして参照できるようにする
        activationScript = "${config.system.activationScript}";
      };
      isExecutable = true;
    };
    # --- カスタムカーネルの定義 ---
    customKernel = pkgs.linux.override {
      structuredExtraConfig = with lib.kernel; {
        "9P_FS" = yes;
        "9P_FS_POSIX_ACL" = yes;
        NET_9P = yes;
        NET_9P_VIRTIO = yes;
        VIRTIO_PCI = yes;
        VIRTIO_NET = yes;
        VIRTIO_BLK = yes;
        PCI = yes;
      };
    };

    kernelVersion = customKernel.modDirVersion;

    # --- initrd の定義 ---
    initrd = pkgs.makeInitrdNG {
      name = "stage1-initrd";
      contents = [
        {
          source = pkgs.replaceVarsWith {
            src = ./stage1.sh;
            replacements = {
              inherit kernelVersion;
              stage2Init = "${stage2Init}";
              systemPath = config.system.path;
            };
            isExecutable = true;
            dontPatchShebangs = true;
          };
          target = "/init";
        }
        {
          source = "${pkgs.pkgsStatic.busybox}/bin/busybox";
          target = "/bin/busybox";
        }
        {
          source = "${pkgs.pkgsStatic.busybox}/bin/busybox";
          target = "/bin/sh";
        }
      ];
    };
  in {
    # ここでエクスポートする！
    system.build.kernel = customKernel;
    system.build.initrd = initrd;
    system.build.stage2Init = stage2Init;
  };
}
