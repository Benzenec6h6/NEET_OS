{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.programs.neet-helper;
  inieet = pkgs.callPackage ../../pkgs/inieet {};

  adminDir = "/run/neet-admin";
  socketPath = "${adminDir}/sock";
  neetBin = "${inieet.neetHelper}/bin/neet";

  wrappedNeet = pkgs.symlinkJoin {
    name = "neet-wrapped";
    paths = [inieet.neetHelper];
    buildInputs = [pkgs.makeWrapper];
    postBuild = ''
      wrapProgram $out/bin/neet \
        --set NEET_ADMIN_SOCK "${socketPath}" \
        --set NEET_S6_SUDO "${pkgs.s6}/bin/s6-sudo" \
        --set NEET_ROM "${pkgs.rom}/bin/rom" \
        --set NEET_KEEP_DIRENV "${boolToString cfg.gc.keepDirenv}" \
        ${optionalString (cfg.flake != null) "--set NEET_FLAKE \"${cfg.flake}\""}
    '';
  };
in {
  options.programs.neet-helper = {
    enable = mkEnableOption "neet-helper (system management CLI with s6-sudo)";

    flake = mkOption {
      type = types.nullOr types.str;
      default = "/etc/neet-os";
      description = "デフォルトで使用する Flake リポジトリのパス";
    };

    allowedGroup = mkOption {
      type = types.str;
      default = "wheel";
      description = "neet-helper によるシステム切り替えを許可するグループ名";
    };

    gc = {
      keepDirenv = mkOption {
        type = types.bool;
        default = true;
        description = ''
          Whether to preserve nix-direnv environment caches during garbage collection.
          When false, stale/all direnv gcroots may be cleared before running GC.
        '';
      };

      keepGenerations = mkOption {
        type = types.nullOr types.int;
        default = 5;
        description = "GC 時に残す最新のシステム世代数 (null の場合は日数指定や全削除に従う)";
      };
    };
  };

  config = mkIf cfg.enable {
    environment.systemPackages = [wrappedNeet];

    system.stateDirectories = [
      {
        path = adminDir;
        mode = "0750";
        user = "root";
        group = cfg.allowedGroup;
      }
    ];

    system.s6-rc.services.neet-admin-server = {
      type = "longrun";
      autoStart = true;
      log.enable = true;
      run = ''
        #!/bin/sh
        exec 2>&1

        export PATH="/run/wrappers/bin:/run/current-system/sw/bin:/run/current-system/bin:/bin:/sbin"
        export NIX_REMOTE="daemon"
        export HOME="/root"
        export NEET_ALLOWED_GROUP="${cfg.allowedGroup}"

        rm -f ${socketPath}

        exec ${pkgs.s6}/bin/s6-ipcserver -a 0666 ${socketPath} \
          ${pkgs.s6}/bin/s6-sudod ${neetBin} priv
      '';
    };
  };
}
