{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.testing.vm;
  otherConsoles = builtins.tail config.boot.consoles;
  primaryConsole = builtins.head config.boot.consoles;
  kernelConsoleArgs = lib.concatMapStringsSep " " (c: "console=${c}") (otherConsoles ++ [primaryConsole]);

  vmRunnerScript = pkgs.replaceVarsWith {
    src = ./run-vm.sh; # 同一ディレクトリルートにあるスクリプトテンプレート
    replacements = {
      qemuBinary = "${pkgs.qemu_kvm}/bin/qemu-system-x86_64";
      kernel = "${config.system.build.kernel}";
      initrd = "${config.system.build.initrd}";
      diskImage = "${config.system.build.diskImage}";
      memorySize = toString cfg.memorySize;
      cores = toString cfg.cores;
      cmdline = "${kernelConsoleArgs} loglevel=7 printk.time=1 console_msg_format=syslog";
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
      default = 1024;
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
      description = "Enable GTK display output (false = headless/serial only)";
    };
    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "Disk image size in MiB";
    };
    persistent = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "false: snapshot=on (使い捨て), true: 永続化テスト用";
    };
    sharedStore = lib.mkEnableOption "9p経由でホストのnix storeを共有(反復開発の高速化用)";

    sharedConfig = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "9p経由でホストの設定ディレクトリを/etc/neet-osに共有";
    };

    # ★ついでに共有するホスト側パスも指定できるようにしておくと柔軟
    sharedConfigPath = lib.mkOption {
      type = lib.types.str;
      default = "";
      description = "ホスト側の共有ディレクトリパス（空なら起動スクリプト実行時のPWD）";
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
