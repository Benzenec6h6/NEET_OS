{
  config,
  pkgs,
  lib,
  ...
}: let
  # 1. 有効なファイルシステムのツール群
  extraFsPackages = lib.concatLists (
    lib.catAttrs "packages" (lib.attrValues (
      lib.filterAttrs (_: fs: fs.enable) config.boot.initrd.supportedFilesystems
    ))
  );

  # 2. Stage 1 で優先して含めたいバイナリ・パッケージ群の宣言
  primaryPackages =
    [
      # 自作ツール・スクリプト
      config.system.build.stage1Mount
      config.system.build.neetSecret
      config.system.build.mdevdDisk

      # デーモン
      pkgs.pkgsStatic.mdevd

      # util-linux から必須コマンドだけを抽出
      (pkgs.runCommand "initrd-util-linux" {} ''
        mkdir -p $out/bin
        for b in mount umount losetup blkid fdisk fsck switch_root; do
          p="${pkgs.pkgsStatic.util-linux}/bin/$b"
          [ ! -f "$p" ] && p="${pkgs.pkgsStatic.util-linux}/sbin/$b"
          cp -f "$p" $out/bin/
        done
      '')

      # kmod (modprobe として配置)
      (pkgs.runCommand "initrd-kmod" {} ''
        mkdir -p $out/bin
        cp -f "${pkgs.pkgsStatic.kmod}/bin/kmod" $out/bin/modprobe
      '')
    ]
    ++ extraFsPackages;

  # 3. 優先パッケージ群を 1 つのツリーにまとめる
  primaryBin = pkgs.buildEnv {
    name = "initrd-primary-bin";
    paths = primaryPackages;
  };

  # 4. BusyBox と優先バイナリを合成して initrdEnv を作成
  # （スクリプトが数行に縮んだため、runCommand にインライン化）
  initrdEnv = pkgs.runCommand "initrd-env" {} ''
    mkdir -p "$out/bin"

    # 宣言された優先バイナリ群をコピー (bin / sbin 両対応)
    if [ -d "${primaryBin}/bin" ]; then
      cp -fL "${primaryBin}/bin/"* "$out/bin/"
    fi
    if [ -d "${primaryBin}/sbin" ]; then
      cp -fL "${primaryBin}/sbin/"* "$out/bin/"
    fi

    # サブツールとして BusyBox を配置
    cp -fL "${pkgs.pkgsStatic.busybox}/bin/busybox" "$out/bin/busybox"
    chmod 755 "$out/bin/"*

    # 既存の優先バイナリを上書きせずに、足りないコマンドを BusyBox リンクで埋める
    cd "$out/bin"
    for app in $(./busybox --list); do
      if [ ! -e "$app" ]; then
        ln -s busybox "$app"
      fi
    done
  '';

  modulesClosure = pkgs.makeModulesClosure {
    kernel = config.system.modulesTree;
    rootModules = lib.unique config.boot.initrd.availableKernelModules;
    firmware = config.hardware.firmware;
    allowMissing = true;
  };
in {
  options.boot.initrd = {
    availableKernelModules = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [];
      description = "Stage 1 で利用可能にするモジュール";
    };
    prepend = lib.mkOption {
      type = lib.types.listOf lib.types.path;
      default = [];
      description = "initrd の先頭に連結する非圧縮 cpio イメージのリスト（マイクロコード等）";
    };
    extraContents = lib.mkOption {
      type = lib.types.listOf lib.types.attrs;
      default = [];
      example = [
        {
          source = "/path/to/file";
          target = "/etc/file";
        }
      ];
      description = "initrd の cpio に追加するファイル群 (source と target のペア)";
    };
  };

  config = {
    system.build.debugModulesClosure = modulesClosure;
    system.build.initrd = pkgs.makeInitrdNG {
      name = "stage1-initrd";
      prepend = config.boot.initrd.prepend;
      contents =
        [
          {
            source = config.system.build.stage1Script;
            target = "/init";
          }
          {
            source = "${initrdEnv}/bin";
            target = "/bin";
          }
          {
            source = "${modulesClosure}/lib";
            target = "/lib";
          }
          {
            source = pkgs.writeText "mdev.conf" config.boot.initrd.mdevd.rules;
            target = "/etc/mdev.conf";
          }
          {
            source = config.system.build.stage1MountPlan;
            target = "/mount-plan.json";
          }
        ]
        ++ config.boot.initrd.extraContents
        ++ (lib.mapAttrsToList (name: secret: {
          source = secret.file;
          target = "/etc/secrets/${name}.age";
        }) (lib.filterAttrs (_: s: s.inInitrd or false) config.neet.secrets));
    };
  };
}
