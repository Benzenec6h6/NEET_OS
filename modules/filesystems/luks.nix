{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.boot.initrd.luks;

  deviceOpts = {name, ...}: {
    options = {
      name = mkOption {
        type = types.str;
        default = name;
        description = "マッパー名 (/dev/mapper/<name>)";
      };
      device = mkOption {
        type = types.str;
        example = "/dev/disk/by-partuuid/xxxx";
        description = "暗号化された実デバイスのパス (/dev/disk/by-* 等)";
      };
      keyFile = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "キーファイルのパス（null の場合は TTY からパスフレーズ入力）";
      };
      allowDiscards = mkOption {
        type = types.bool;
        default = true;
        description = "SSD の TRIM (discard) を有効化するか";
      };
      extraOpenArgs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "cryptsetup open に渡す追加引数";
      };
    };
  };

  unlockCommands = concatStringsSep "\n" (
    mapAttrsToList (_: dev: let
      args =
        optional dev.allowDiscards "--allow-discards"
        ++ optional (dev.keyFile != null) "--key-file ${dev.keyFile}"
        ++ dev.extraOpenArgs;
      argsStr = concatStringsSep " " args;
    in ''
      # --- Device: ${dev.name} ---
      echo "NEET OS Stage 1: Waiting for LUKS device ${dev.device}..."
      _luks_timeout=100
      while [ ! -b "${dev.device}" ] && [ $_luks_timeout -gt 0 ]; do
          sleep 0.1
          _luks_timeout=$((_luks_timeout - 1))
      done

      if [ ! -b "${dev.device}" ]; then
          die "LUKS device ${dev.device} did not appear in time!"
      fi

      if [ ! -e "/dev/mapper/${dev.name}" ]; then
          echo "NEET OS Stage 1: Unlocking LUKS device ${dev.name} (${dev.device})..."
          cryptsetup open ${argsStr} "${dev.device}" "${dev.name}" \
              || die "Failed to unlock LUKS device ${dev.device}"
      fi
    '')
    cfg.devices
  );
in {
  options.boot.initrd.luks = {
    devices = mkOption {
      type = types.attrsOf (types.submodule deviceOpts);
      default = {};
      description = "Stage 1 で解除する LUKS デバイス一覧";
    };
  };

  options.boot.initrd.supportedFilesystems.luks = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "initrd 内で LUKS を有効にするかどうか";
    };

    packages = mkOption {
      type = with types; listOf package;
      default = [];
      description = "initrd 内に含める LUKS 関連パッケージ (cryptsetup 等)";
    };
  };

  # （念のため Stage 2 側も btrfs と揃えておく）
  options.boot.supportedFilesystems.luks = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "システムで LUKS を有効にするかどうか";
    };

    packages = mkOption {
      type = with types; listOf package;
      default = [];
      description = "システムに含める LUKS 関連パッケージ";
    };
  };

  config = mkIf (cfg.devices != {}) {
    # 1. build-initrd.sh 経由で cryptsetup 静的バイナリを組み込む
    boot.initrd.supportedFilesystems.luks = {
      enable = true;
      packages = [pkgs.pkgsStatic.cryptsetup];
    };

    # 2. 必要なカーネルモジュール（暗号アルゴリズムと device-mapper）
    boot.initrd.availableKernelModules = [
      "dm_mod"
      "dm_crypt"
      "aes"
      "sha256"
      "xts"
    ];

    # 3. mdev.conf に dm デバイス用のパーミッションを追加
    services.mdevd.rules = ''
      dm-[0-9].* 0:0 660
    '';

    # 4. stage1.sh に埋め込む文字列
    system.build.luksUnlockCommands = unlockCommands;
  };
}
