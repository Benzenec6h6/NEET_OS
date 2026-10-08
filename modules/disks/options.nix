{
  lib,
  pkgs,
  ...
}: let
  inherit (lib) mkOption types;

  subvolumeOpts = {
    options = {
      mountPoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "マウント先。null の場合は subvolume を作るだけでマウントしない";
      };
      options = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["compress=zstd" "noatime"];
        description = "マウントオプション（subvol= は自動で付く）";
      };
      neededForBoot = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "null の場合は自動判定（/ /nix /nix/store /usr、impermanence 有効時は persistPath、resetOnBoot=true のもの）";
      };
      resetOnBoot = mkOption {
        type = types.bool;
        default = false;
        description = "起動時に旧 subvolume を old_roots/ へ退避して作り直す（init-core が実行）";
      };
      keepOldRoots = mkOption {
        type = types.ints.unsigned;
        default = 3;
        description = "resetOnBoot 時に残す旧世代数";
      };
    };
  };

  contentOpts = {
    options = {
      type = mkOption {
        type = types.enum ["vfat" "ext4" "btrfs" "swap" "luks"];
        description = "ファイルシステムまたはコンテナの種類";
      };
      label = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "null の場合はパーティション名";
      };
      uuid = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "mkfs / luksFormat に渡す UUID";
      };
      mountPoint = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "マウント先（btrfs subvolume や LUKS の場合は null）";
      };
      options = mkOption {
        type = types.listOf types.str;
        default = ["defaults"];
        description = "マウントオプション";
      };
      neededForBoot = mkOption {
        type = types.nullOr types.bool;
        default = null;
        description = "起動時に必要かどうかの明示指定";
      };
      extraMkfsArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "mkfs に追加で渡す引数";
      };
      subvolumes = mkOption {
        type = types.attrsOf (types.submodule subvolumeOpts);
        default = {};
        description = "btrfs の subvolume";
      };

      # ★ LUKS 専用オプション
      luksName = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "マッパー名 (/dev/mapper/<name>)。null の場合は 'crypt_<partition.name>'";
      };
      content = mkOption {
        type = types.nullOr (types.submodule contentOpts);
        default = null;
        description = "LUKS 内部のコンテンツ (btrfs, ext4 など)";
      };
      extraLuksArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "cryptsetup luksFormat に追加で渡す引数";
      };
    };
  };

  partitionOpts = {
    options = {
      name = mkOption {
        type = types.str;
        description = "GPT のパーティション名（ディスク内で一意）";
      };
      size = mkOption {
        type = types.str;
        default = "100%";
        example = "512M";
        description = "K/M/G/T 付きのサイズ、または 100%（残り全部。最後のパーティションのみ）";
      };
      typeCode = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "sgdisk の typecode。null の場合は content から決定（vfat=ef00, swap=8200, 他=8300）";
      };
      guid = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "パーティション GUID（PARTUUID）。null の場合は <disk>/<partition> から決定的に生成";
      };
      content = mkOption {
        type = types.nullOr (types.submodule contentOpts);
        default = null;
        description = "パーティションの中身。null なら未フォーマットのまま";
      };
    };
  };

  diskOpts = {
    options = {
      device = mkOption {
        type = types.nullOr types.str;
        default = null;
        example = "/dev/disk/by-id/nvme-XXXX";
        description = "実機のデバイス（/dev/disk/by-* のみ）。null ならイメージ生成専用、実機では --device で指定";
      };
      partitions = mkOption {
        type = types.listOf (types.submodule partitionOpts);
        default = [];
        description = "GPT 上の並び順そのままのパーティション一覧";
      };
    };
  };
in {
  options.disks = {
    devices = mkOption {
      type = types.attrsOf (types.submodule diskOpts);
      default = {};
      description = "ディスク構成の宣言。ここから disk-plan.json と boot.fileSystems（mkDefault）を導出する";
    };
    deviceReference = mkOption {
      type = types.enum ["partuuid" "uuid"];
      default = "partuuid";
      description = ''
        boot.fileSystems.*.device に使う識別子。
        どちらも /dev/disk/by-* が initrd で作られることが前提（mdevd-disk.sh を確認）。
      '';
    };
    package = mkOption {
      type = types.package;
      default = (pkgs.callPackage ../../pkgs/inieet {}).diskSetup;
      description = "disk-setup バイナリを含むパッケージ（pkgs/inieet のビルド成果物）";
    };
  };
}
