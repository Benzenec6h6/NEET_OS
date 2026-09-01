{
  pkgs,
  config,
  ...
}: let
  closure = pkgs.closureInfo {
    rootPaths = [
      config.system.build.toplevel
      config.boot.kernelPackages.kernel
    ];
  };

  rootfs = pkgs.runCommand "rootfs-staging" {} ''
    mkdir -p $out
    while read -r path; do
      cp -a "$path" "$out/$(basename "$path")"
    done < ${closure}/store-paths
  '';
in
  pkgs.runCommand "neet-os-disk-image" {
    nativeBuildInputs = [pkgs.e2fsprogs];
  } ''
    truncate -s 2G $out
    # -d で rootfs (内部に /nix/store を含む) をディスクに流し込む
    mkfs.ext4 -L NEET_OS -d ${rootfs} $out
  ''
