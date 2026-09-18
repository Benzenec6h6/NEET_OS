{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.testing.vm;
  rootFsType = config.boot.fileSystems."/".fsType;

  toplevel = config.system.build.toplevel;

  closure = pkgs.closureInfo {
    rootPaths = [
      toplevel
      config.boot.kernelPackages.kernel
    ];
  };

  # スクリプトを外部ファイルとして呼び出す
  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${./populate-rootfs.sh}
    '';

  diskImage = let
    imageSize = "2G";
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
