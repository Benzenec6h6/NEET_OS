{
  pkgs,
  kernel,
  initrd,
  image,
  ...
}: let
  qemuArgs = [
    "-kernel ${kernel}/bzImage"
    "-initrd ${initrd}/initrd"
    "-m 1024" # 少し増やしておくと安心
    "-device virtio-rng-pci"

    # 【変更】シリアルコンソールは維持しつつ、グラフィックを有効にする
    "-serial stdio"
    "-display gtk" # 環境により "sdl" や "spice-app"、macOSなら "cocoa"
    "-vga none" # 標準VGAを無効化してvirtio-gpuに絞る

    #"-append \"console=ttyS0 console=tty1 panic=0 net.ifnames=0\""
    "-append \"console=tty1 console=ttyS0 panic=0 net.ifnames=0\""
    "-no-reboot"
    "-netdev user,id=net0 -device virtio-net-pci,netdev=net0"

    #"-fsdev local,security_model=none,id=fsdev-store,path=/nix/store,readonly=on"
    #"-device virtio-9p-pci,fsdev=fsdev-store,mount_tag=nixstore"

    "-drive file=${image},if=virtio,format=raw,snapshot=on"

    # GPU
    "-device virtio-gpu-pci"

    # 【変更】マウスではなくタブレットデバイスを使う（マウスカーソルが同期します）
    "-device virtio-keyboard-pci"
    "-device virtio-tablet-pci"

    "-device intel-hda -device hda-duplex"
  ];
in
  pkgs.writeShellScriptBin "run-vm" ''
    # GUIを表示するために、ホストの環境変数を継承してQEMUを叩く
    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 ${pkgs.lib.concatStringsSep " " qemuArgs} "$@"
  ''
