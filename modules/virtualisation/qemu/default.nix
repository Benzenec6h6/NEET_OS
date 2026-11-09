{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.virtualisation.qemu;

  netdevArgs = let
    fwdArgs =
      lib.concatMapStrings (
        f: ",hostfwd=${f.proto}::${toString f.hostPort}-:${toString f.guestPort}"
      )
      cfg.forwardPorts;
  in "user,id=net0${fwdArgs}";

  vmRunnerScript = pkgs.replaceVarsWith {
    src = ./run-vm.sh;
    replacements = {
      qemuBinary = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
      qemuImgBinary = "${pkgs.qemu_kvm}/bin/qemu-img";
      ovmfCode = "${pkgs.OVMF.firmware}";
      ovmfVars = "${pkgs.OVMF.variables}";
      diskImage = "${config.system.build.diskImage}";
      memorySize = toString cfg.memorySize;
      cores = toString cfg.cores;
      inherit netdevArgs;
      enableGraphics =
        if cfg.graphics
        then "1"
        else "0";
      enableSharedStore =
        if cfg.sharedStore
        then "1"
        else "0";
      isPersistent =
        if cfg.persistent
        then "1"
        else "0";
      enableSharedConfig =
        if cfg.sharedConfig
        then "1"
        else "0";
      sourcePath = cfg.sharedConfigPath;
    };
    isExecutable = true;
    dontPatchShebangs = true;
  };
in {
  options.virtualisation.qemu = {
    enable = lib.mkEnableOption "Build this configuration as a QEMU test VM runner";

    forwardPorts = lib.mkOption {
      type = lib.types.listOf (lib.types.submodule {
        options = {
          hostPort = lib.mkOption {
            type = lib.types.port;
            description = "ホスト側で待ち受けるポート";
          };
          guestPort = lib.mkOption {
            type = lib.types.port;
            default = 22;
            description = "ゲスト (VM) 側の転送先ポート";
          };
          proto = lib.mkOption {
            type = lib.types.enum ["tcp" "udp"];
            default = "tcp";
            description = "プロトコル";
          };
        };
      });
      default = [];
      description = "ホストから VM へ転送するポートフォワードのリスト";
    };

    memorySize = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "VM memory in MiB";
    };
    cores = lib.mkOption {
      type = lib.types.int;
      default = 4;
      description = "Number of CPU cores for the VM";
    };
    graphics = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Enable GTK display output";
    };
    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
      description = "Disk image size in MiB";
    };
    persistent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "false: snapshot=on (使い捨て), true: 差分オーバーレイをローカルに保存して永続化";
    };
    sharedStore = lib.mkEnableOption "9p経由でホストのnix storeを共有";
    sharedConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "9p経由でホストの設定ディレクトリを/etc/neet-osに共有";
    };
    sharedConfigPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ホスト側の共有ディレクトリパス";
    };
  };

  config = lib.mkIf cfg.enable {
    # ★ VM 有効化時に raw ディスクイメージビルダーを自動連動
    images.raw = {
      enable = lib.mkDefault true;
      diskSize = lib.mkDefault cfg.diskSize;
    };

    virtualisation.virtio.enable = lib.mkDefault true;
    boot.vt.enable = lib.mkDefault true;
    boot.serial.enable = lib.mkDefault true;
    boot.primaryConsole = lib.mkDefault "serial";

    boot.fileSystems."/etc/neet-os" = lib.mkIf cfg.sharedConfig {
      device = "neet_os_src";
      fsType = "9p";
      options = [
        "trans=virtio"
        "version=9p2000.L"
        "msize=1048576"
        "nofail"
      ];
    };

    system.build.vm = pkgs.stdenv.mkDerivation {
      name = "run-vm";
      buildCommand = ''
        mkdir -p $out/bin
        ln -s ${vmRunnerScript} $out/bin/run-vm
      '';
    };
  };
}
