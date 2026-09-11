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
  };

  config = lib.mkIf cfg.enable {
    # 1. VM環境でのOS側フラグ・コンソール調整 (旧 vm-variant.nix から移設)
    virtualisation.virtio.enable = lib.mkDefault true;
    boot.consoles = lib.mkDefault (
      if cfg.graphics
      then ["ttyS0" "tty1"]
      else ["ttyS0"]
    );

    # 2. replaceVarsWith で生成したスクリプトを出力 (新 runner.nix の処理)
    system.build.vm = pkgs.stdenv.mkDerivation {
      name = "run-vm";
      buildCommand = ''
        mkdir -p $out/bin
        ln -s ${vmRunnerScript} $out/bin/run-vm
      '';
    };
  };
}
