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
    nativeBuildInputs = [pkgs.btrfs-progs];
  } ''
    # 1. イメージ内の構造を /nix/store に合わせる
    mkdir -p ./staging/nix/store

    # 2. ストアパスを /nix/store の下にコピー
    cp -a ${rootfs}/* ./staging/nix/store/

    truncate -s 2G $out
    # staging (中身は nix/store/...) をルートとして書き込む
    mkfs.btrfs -L NEET_OS -r ./staging $out
  ''
