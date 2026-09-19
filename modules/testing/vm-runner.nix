{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.testing.vm;

  vmRunnerScript = pkgs.replaceVarsWith {
    src = ./run-vm.sh;
    replacements = {
      qemuBinary = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
      ovmfFirmware = "${pkgs.OVMF.fd}/FV/OVMF.fd";
      diskImage = "${config.system.build.diskImage}";
      memorySize = toString cfg.memorySize;
      cores = toString cfg.cores;
      enableGraphics =
        if cfg.graphics
        then "1"
        else "0";
      enableSharedStore =
        if cfg.sharedStore
        then "1"
        else "0";
      snapshotFlag =
        if cfg.persistent
        then ""
        else ",snapshot=on";
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
  options.testing.vm = {
    enable = lib.mkEnableOption "Build this configuration as a QEMU test VM";
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
      description = "false: snapshot=on (使い捨て), true: 変更をディスクに永続化";
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
    virtualisation.virtio.enable = lib.mkDefault true;
    boot.consoles = lib.mkDefault (
      if cfg.graphics
      then ["ttyS0" "tty1"]
      else ["ttyS0"]
    );

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
