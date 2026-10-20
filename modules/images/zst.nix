{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.images.zst;
  toplevel = config.system.build.toplevel;
  kernel = config.boot.kernelPackages.kernel;
  isInstaller = config.installer.enable or false;

  # カーネルパラメータを文字列として結合
  kernelParamsStr = lib.concatStringsSep " " config.boot.kernelParams;

  # ★ ここで直接 writeText を呼ぶ（循環しない安全な定義）
  limineConf = pkgs.writeText "limine.conf" ''
    timeout: 5

    /NEET OS Live Installer
        protocol: linux
        kernel_path: boot():/kernels/gen-1-vmlinuz
        module_path: boot():/kernels/gen-1-initrd
        cmdline: init=${toplevel}/init ${kernelParamsStr}
  '';

  closure = pkgs.closureInfo {
    rootPaths = [
      toplevel
      kernel
    ];
  };

  rootfs =
    pkgs.runCommand "rootfs-staging" {
      nativeBuildInputs = [pkgs.nix pkgs.bash];
      inherit closure toplevel;
    } ''
      bash ${../testing/populate-rootfs.sh}
    '';

  bootloader =
    if (config.boot.loader.efistub.enable or false)
    then "efistub"
    else if (config.boot.loader.limine.enable or false)
    then "limine"
    else throw "boot.loader.limine または boot.loader.efistub のいずれかを有効にしてください";

  # -------------------------------------------------------------
  # A. Live インストーラ用イメージビルダー (SquashFS + GPT)
  # -------------------------------------------------------------
  liveDiskImageZst =
    pkgs.runCommand "neet-live-image.img.zst" {
      nativeBuildInputs =
        [
          pkgs.squashfs-tools
          pkgs.gptfdisk
          pkgs.dosfstools
          pkgs.mtools
          pkgs.coreutils
          pkgs.zstd
        ]
        ++ lib.optional (bootloader == "limine") pkgs.limine;

      inherit toplevel bootloader;
      espSizeM = 512;
    } ''
      set -euo pipefail

      echo "images.zst (live): building SquashFS rootfs..."
      # 1. rootfs を zstd で高圧縮した SquashFS を生成
      mksquashfs "${rootfs}" rootfs.squashfs -comp zstd -Xcompression-level 19 -noappend

      sqfsBytes=$(stat -c%s rootfs.squashfs)
      sqfsSizeM=$(( (sqfsBytes + 1048576 - 1) / 1048576 ))
      # ESP(512MB) + SquashFS + マージン(32MB) でイメージ全体のサイズを動的に決定
      totalSizeM=$(( espSizeM + sqfsSizeM + 32 ))

      echo "images.zst (live): creating raw disk image (total: ''${totalSizeM}M, squashfs: ''${sqfsSizeM}M)..."
      truncate -s "''${totalSizeM}M" raw.img

      # 2. GPT パーティション作成 (PARTLABEL を NEET_BOOT と NEET_LIVE に設定)
      sgdisk --clear raw.img
      sgdisk --new=1:2048:+''${espSizeM}M --typecode=1:ef00 --change-name=1:"NEET_BOOT" raw.img
      sgdisk --new=2:0:0                  --typecode=2:8300 --change-name=2:"NEET_LIVE" raw.img

      # 3. ESP (FAT32) の構築
      echo "images.zst (live): populating ESP..."
      espImg="esp.img"
      truncate -s "''${espSizeM}M" "$espImg"
      mkfs.vfat -F 32 -n "NEET_BOOT" "$espImg"

      mmd -i "$espImg" ::EFI ::EFI/BOOT ::kernels
      if [ "$bootloader" = "limine" ]; then
        mcopy -i "$espImg" "${pkgs.limine}/share/limine/BOOTX64.EFI" ::EFI/BOOT/BOOTX64.EFI
        mcopy -i "$espImg" "${toplevel}/kernel" ::kernels/gen-1-vmlinuz
        mcopy -i "$espImg" "${toplevel}/initrd" ::kernels/gen-1-initrd

        # ★ ヒアドキュメントを削除し、writeText で作ったファイルを直接コピー
        mcopy -i "$espImg" "${limineConf}" ::limine.conf
      fi

      # 4. 生イメージへの焼き込み
      # ESP をセクタ 2048 (1MiB オフセット) に書き込む
      dd if="$espImg" of=raw.img bs=1M seek=1 conv=notrunc

      # SquashFS をパーティション 2 の開始セクタに直接 dd で書き込む
      startSector=$(sgdisk -p raw.img | awk '$1 == "2" {print $2}')
      dd if=rootfs.squashfs of=raw.img bs=512 seek="$startSector" conv=notrunc

      # 5. zstd で圧縮してディレクトリに出力
      echo "images.zst (live): compressing to $out..."
      mkdir -p "$out"
      imgName="neet-live-image.img.zst"
      zstd -T0 -19 raw.img -o "$out/$imgName"

      # 6. sha256sum.txt の生成
      echo "images.zst (live): generating sha256 checksum..."
      # 相対パスで記録しておくと、配布先で `sha256sum -c sha256sum.txt` がそのまま通る
      (cd "$out" && sha256sum "$imgName" > sha256sum.txt)
    '';

  # -------------------------------------------------------------
  # B. 通常のインストール済みイメージビルダー (既存の処理)
  # -------------------------------------------------------------
  espMount = lib.findFirst (mp: config.boot.fileSystems.${mp}.fsType == "vfat") "/boot" (
    builtins.attrNames config.boot.fileSystems
  );

  diskImageZst =
    pkgs.runCommand "neet-os-disk-image.img.zst" {
      # ... (既存の build-disk-image.sh を呼ぶ処理そのまま) ...
      nativeBuildInputs =
        [
          config.disks.package
          pkgs.gptfdisk
          pkgs.dosfstools
          pkgs.mtools
          pkgs.btrfs-progs
          pkgs.e2fsprogs
          pkgs.util-linux
          pkgs.coreutils
          pkgs.zstd
        ]
        ++ lib.optional (bootloader == "limine") pkgs.limine;

      inherit toplevel rootfs bootloader espMount;
      diskPlan = config.system.build.diskPlan;
      diskName = lib.optionalString (cfg.disk != null) cfg.disk;
      diskSizeM = toString cfg.diskSize;
      liminePkg = pkgs.limine;
      uefiShellPkg = "${pkgs.edk2-uefi-shell}/shell.efi";
      ukiFile =
        if (config.boot.uki.enable or false)
        then "${config.system.build.uki}"
        else "";
    } ''
      out="raw.img"
      bash ${../testing/build-disk-image.sh}
      echo "images.zst: compressing raw.img to $out..."
      zstd -T0 -19 raw.img -o "$out"
    '';
in {
  options.images.zst = {
    enable = lib.mkEnableOption "img.zst disk image builder";
    disk = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
    };
    diskSize = lib.mkOption {
      type = lib.types.int;
      default = 4096;
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        # Live 時は disks.devices が空でも OK
        assertion = isInstaller || config.disks.devices != {};
        message = "images.zst: ディスクイメージを作るには disks.devices を定義してください。";
      }
    ];

    system.build.diskImageZst =
      if isInstaller
      then liveDiskImageZst
      else diskImageZst;
  };
}
