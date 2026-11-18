{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.boot.modprobe;

  # 生成する modprobe 設定ファイルの中身
  modprobeConfigText = ''
    # Generated declaratively by NEET_OS

    # --- Blacklisted Modules ---
    ${concatMapStringsSep "\n" (name: "blacklist ${name}") cfg.blacklist}

    # --- Extra Configuration (options, alias, etc.) ---
    ${cfg.extraConfig}
  '';

  # initrd 内に持ち込むための Nix Store ファイル
  modprobeConfigFile = pkgs.writeText "50-neet.conf" modprobeConfigText;
in {
  options.boot.modprobe = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to enable declarative modprobe.d configuration.";
    };

    blacklist = mkOption {
      # リスト [ "nouveau" ] でも 属性セット { nouveau = true; } でも受け付け可能
      type = with types;
        coercedTo (listOf str) (enabledList: genAttrs enabledList (_: true)) (attrsOf bool);
      default = {};
      example = ["nouveau" "pcspkr"];
      description = "Kernel modules to blacklist from being automatically loaded.";
      apply = modules: attrNames (filterAttrs (_: v: v) modules);
    };

    extraConfig = mkOption {
      type = types.lines;
      default = "";
      example = ''
        options nvidia-drm modeset=1
        options snd-hda-intel power_save=1
      '';
      description = "Additional configuration text for modprobe.d (options, aliases, etc.).";
    };

    copyToInitrd = mkOption {
      type = types.bool;
      default = true;
      description = "Whether to include the modprobe configuration in Stage 1 (initrd).";
    };
  };

  config = mkIf cfg.enable {
    # 1. Stage 2 用の /etc/modprobe.d/ を生成
    environment.etc."modprobe.d/50-neet.conf".text = modprobeConfigText;

    # 2. Stage 1 (initrd) にも同じ設定を注入（nouveau などの初期誤ロードを防止）
    boot.initrd.extraContents = mkIf cfg.copyToInitrd [
      {
        source = modprobeConfigFile;
        target = "/etc/modprobe.d/50-neet.conf";
      }
    ];

    # 3. カーネルが uevent 等で動的にモジュールを要求した際のハンドラを登録
    #    bin_setup.rs により /bin/modprobe が確実に存在するため /bin/modprobe を指定
    boot.kernel.sysctl = {
      "kernel.modprobe" = mkDefault "/bin/modprobe";
    };

    system.build.modprobeConfigFile = modprobeConfigFile;
  };
}
