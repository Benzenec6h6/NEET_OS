{
  config,
  pkgs,
  lib,
  ...
}: {
  config = lib.mkIf (lib.any (fs: fs.fsType == "btrfs") (lib.attrValues config.boot.stage1.fileSystems)) {
    # Btrfsに必要なカーネルモジュール
    boot.initrd.availableKernelModules = [
      "btrfs"
      "crc32c"
      "xxhash64"
      "sha256"
      "blake2b-256"
    ];

    # Stage 1 (initrd) で btrfs コマンドを使えるようにする
    # (ただし s6-mount があればマウント自体には不要。メンテナンス用)
    environment.systemPackages = [pkgs.pkgsStatic.btrfs-progs];
  };
}
