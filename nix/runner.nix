{
  pkgs,
  kernel,
  initrd,
}: let
  # QEMUのコマンドライン引数をリストで管理すると、
  # 後で条件分岐（例：デバッグ時だけオプションを追加など）しやすくなります。
  qemuArgs = [
    "-kernel ${kernel}/bzImage"
    "-initrd ${initrd}/initrd"
    "-m 512"
    "-nographic"
    "-append \"console=ttyS0 panic=0\""
    "-no-reboot" # パニック時に勝手に再起動させず、ログを保持する
  ];
in
  pkgs.writeShellScriptBin "run-vm" ''
    exec ${pkgs.qemu_kvm}/bin/qemu-system-x86_64 ${pkgs.lib.concatStringsSep " " qemuArgs} "$@"
  ''
