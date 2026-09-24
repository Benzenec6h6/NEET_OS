{
  pkgs,
  config,
  lib,
  ...
}: let
  cfg = config.hardware.nvidia;

  ibtSupport = (cfg.kernelModule == "open") || (cfg.package.ibtSupport or false);

  icd =
    [
      "egl-wayland"
    ]
    ++ lib.optionals (lib.versionAtLeast cfg.package.version "495") [
      "egl-gbm"
    ]
    ++ lib.optionals (lib.versionAtLeast cfg.package.version "560") [
      "egl-wayland2"
      "egl-x11"
    ];

  combineIcdPkgs = pkgs':
    pkgs'.symlinkJoin {
      name = "nvidia-egl-external-platforms${lib.optionalString pkgs'.stdenv.is32bit "-x32"}";
      paths = lib.attrVals icd pkgs';
      postBuild = lib.optionalString (lib.versionOlder cfg.package.version "595") ''
        pushd $out/share/egl/egl_external_platform.d
        for f in [0-9][0-9]_*; do
          num=''${f:0:2}
          rest=''${f:2}
          new=$(printf "%02d" $((99 - 10#$num)))
          mv -- "$f" "tmp-$new$rest"
        done
        for f in tmp-*; do
          mv -- "$f" "''${f#tmp-}"
        done
        popd
      '';
    };
in {
  options.hardware.nvidia = {
    enable = lib.mkEnableOption "NVIDIA driver support";

    modesetting.enable = lib.mkOption {
      type = lib.types.bool;
      default = lib.versionAtLeast cfg.package.version "535";
      description = "Whether to enable kernel modesetting when using the NVIDIA driver.";
    };

    package = lib.mkOption {
      default = config.boot.kernelPackages.nvidiaPackages.stable;
      type = lib.types.package;
      description = "The NVIDIA driver package to use.";
    };

    kernelModule = lib.mkOption {
      type = lib.types.enum [
        "open"
        "closed"
      ];
      default = "open"; # 近年のGPU（RTX 2000番台以降: Turing以降）なら open 推奨
      description = "Whether to use the open source GPU kernel module or closed proprietary one.";
    };

    gsp.enable = lib.mkOption {
      type = lib.types.bool;
      default = cfg.kernelModule == "open" || lib.versionAtLeast cfg.package.version "555";
      description = "Whether to enable the GPU System Processor (GSP).";
    };

    videoAcceleration = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to enable video acceleration (VA-API).";
    };
  };

  config = lib.mkIf cfg.enable {
    # 1. modprobe 設定の注入
    environment.etc = {
      "modprobe.d/nvidia-uvm.conf".text = ''
        softdep nvidia post: nvidia_uvm
      '';

      "modprobe.d/nvidia-blacklists.conf".text = ''
        blacklist nouveau
        options nouveau modeset=0
        blacklist nvidiafb
        blacklist nova_core
      '';

      # 先ほど作った graphics.nix の /run/opengl-driver を参照
      "egl/egl_external_platform.d".source = "/run/opengl-driver/share/egl/egl_external_platform.d/";
    };

    # 2. カーネル外部モジュールとパラメータ
    boot = {
      extraModulePackages =
        if cfg.kernelModule == "open"
        then [cfg.package.open]
        else [cfg.package.mod];

      kernelModules =
        [
          "nvidia"
          "nvidia_modeset"
          "nvidia_drm"
        ]
        ++ lib.optionals (cfg.kernelModule == "open") ["nvidia_uvm"];

      kernelParams =
        lib.optionals (cfg.kernelModule == "open") ["nvidia.NVreg_OpenRmEnableUnsupportedGpus=1"]
        ++ lib.optionals (config.boot.kernelPackages.kernel.kernelAtLeast "6.2" && !ibtSupport) [
          "ibt=off"
        ]
        ++ lib.optionals cfg.modesetting.enable ["nvidia-drm.modeset=1"]
        ++ lib.optionals (cfg.modesetting.enable && lib.versionAtLeast cfg.package.version "545") [
          "nvidia-drm.fbdev=1"
        ];
    };

    # 3. mdevd 用のキャラクタデバイス作成スクリプト (先人の知恵)
    services.mdevd.rules = let
      nvidiaMdevScript = pkgs.writeScript "mdevd-nvidia.sh" ''
        #!/bin/sh
        case "$MDEV" in
          nvidia)
            mknod -m 666 /dev/nvidiactl c 195 255
            for i in $(cat /proc/driver/nvidia/gpus/*/information 2>/dev/null | grep Minor | cut -d ' ' -f 4); do
              mknod -m 666 "/dev/nvidia$i" c 195 "$i"
            done
            ;;
          nvidia_modeset)
            mknod -m 666 /dev/nvidia-modeset c 195 254
            ;;
          nvidia_uvm)
            uvm_major=$(grep nvidia-uvm /proc/devices | cut -d ' ' -f 1)
            mknod -m 666 /dev/nvidia-uvm c "$uvm_major" 0
            mknod -m 666 /dev/nvidia-uvm-tools c "$uvm_major" 1
            ;;
        esac
      '';
    in ''
      nvidia          0:0 666 ! @${nvidiaMdevScript}
      nvidia_modeset  0:0 666 ! @${nvidiaMdevScript}
      nvidia_uvm      0:0 666 ! @${nvidiaMdevScript}
    '';

    # 4. graphics.nix へのライブラリ合流
    hardware.graphics.extraPackages =
      [
        cfg.package.out
        (combineIcdPkgs pkgs)
      ]
      ++ lib.optionals cfg.videoAcceleration [pkgs.nvidia-vaapi-driver];

    hardware.graphics.extraPackages32 = [
      cfg.package.lib32
      (combineIcdPkgs pkgs.pkgsi686Linux)
    ];

    # 5. GSP ファームウェアの提供
    hardware.firmware = lib.optional cfg.gsp.enable cfg.package.firmware;

    # 6. nvidia-smi などの CLI ツール
    environment.systemPackages = [cfg.package.bin];
  };
}
