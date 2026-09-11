{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.testing.vm;
  rootFsType = config.boot.fileSystems."/".fsType;

  closure = pkgs.closureInfo {
    rootPaths = [
      config.system.build.toplevel
      config.boot.kernelPackages.kernel
    ];
  };

  rootfs = pkgs.runCommand "rootfs-staging" {} ''
    mkdir -p $out/nix/store
    while read -r path; do
      cp -a "$path" "$out/nix/store/$(basename "$path")"
    done < ${closure}/store-paths
  '';

  diskImage = let
    imageSize = "2G"; # 将来的にはtesting.vm.diskSizeのようなoptionから受け取る
  in
    {
      btrfs =
        pkgs.runCommand "neet-os-disk-image" {
          nativeBuildInputs = [pkgs.btrfs-progs];
        } ''
          truncate -s ${imageSize} $out
          mkfs.btrfs -L NEET_OS -r ${rootfs} $out
        '';

      ext4 =
        pkgs.runCommand "neet-os-disk-image" {
          nativeBuildInputs = [pkgs.e2fsprogs];
        } ''
          truncate -s ${imageSize} $out
          mkfs.ext4 -L NEET_OS -d ${rootfs} $out
        '';
    }
    .${
      rootFsType
    } or (throw "テストイメージ生成は fsType=${rootFsType} に未対応です (btrfs/ext4のみ対応)");
in {
  config = lib.mkIf cfg.enable {
    system.build.diskImage = diskImage;
  };
}
