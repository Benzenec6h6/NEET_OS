{
  pkgs,
  kernel,
  initrd,
  ...
}: let
  qemuArgs = [
    "-kernel ${kernel}/bzImage"
    "-initrd ${initrd}/initrd"
    "-m 512"
    "-device virtio-rng-pci"
    "-nographic"
    "-append \"console=ttyS0 panic=0 net.ifnames=0\""
    "-no-reboot"
    "-netdev user,id=net0 -device virtio-net-pci,netdev=net0"

    # 【追加】ホストの /nix/store を読み取り専用で共有する
    # mount_tag=nixstore という名前でVM内から見えるようにする
    "-fsdev local,security_model=none,id=fsdev-store,path=/nix/store,readonly=on"
    "-device virtio-9p-pci,fsdev=fsdev-store,mount_tag=nixstore"
  ];
in
  pkgs.writeShellScriptBin "run-vm" ''
    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 ${pkgs.lib.concatStringsSep " " qemuArgs} "$@"
  ''
