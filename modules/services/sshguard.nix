{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.sshguard;
  format = pkgs.formats.keyValue {};

  whitelistFile = pkgs.writeText "sshguard.whitelist" (
    concatStringsSep "\n" cfg.whitelist + "\n"
  );

  confFile = format.generate "sshguard.conf" (
    filterAttrs (_: v: v != null) (
      cfg.settings
      // {
        BACKEND = "${cfg.package}/libexec/sshg-fw-${cfg.settings.BACKEND}";
      }
      // optionalAttrs (cfg.whitelist != []) {
        WHITELIST_FILE = "${whitelistFile}";
      }
    )
  );
in {
  options.services.sshguard = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable sshguard service.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.sshguard;
      description = "The sshguard package to use.";
    };

    whitelist = mkOption {
      type = types.listOf types.str;
      default = [];
      example = ["192.168.1.0/24" "127.0.0.1"];
      description = "List of IPv4/IPv6 addresses, CIDRs, or hostnames to whitelist.";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = format.type;

        options = {
          BACKEND = mkOption {
            type = types.enum ["nft-sets"];
            default = "nft-sets";
            description = "Firewall backend to use.";
          };

          FILES = mkOption {
            type = with types; listOf str;
            # syslog サービスが有効なら /var/log/auth/current を監視
            default = optional config.services.syslog.enable "/var/log/auth/current";
            apply = concatStringsSep " ";
            description = "Log files to monitor.";
            example = ["/var/log/auth/current"];
          };
        };
      };
      default = {};
      description = "Configuration written to sshguard.conf.";
    };
  };

  config = mkIf cfg.enable {
    networking.nftables.enable = mkIf (cfg.settings.BACKEND == "nft-sets") true;

    environment.etc."sshguard.conf".source = confFile;

    system.s6-rc.services.sshguard = {
      type = "longrun";
      dependencies =
        optional config.services.openssh.enable "sshd"
        ++ optional config.services.syslog.enable "syslog"
        ++ optional (cfg.settings.BACKEND == "nft-sets") "nftables";

      run = ''
        #!/bin/sh
        # nft-sets スクリプトが nft コマンドや coreutils を探せるように PATH を指定
        export PATH="${makeBinPath [
          config.networking.nftables.package
          pkgs.coreutils
        ]}:$PATH"

        # 永続ブロック等の DB を保持するディレクトリ
        mkdir -p /var/lib/sshguard

        exec ${cfg.package}/bin/sshguard
      '';

      # sshguard 自身のログ（誰をブロックしたか等）も s6-log で記録
      logRun = ''
        #!/bin/sh
        mkdir -p -m 0750 /var/log/sshguard
        exec ${pkgs.s6}/bin/s6-log -b n10 s500000 /var/log/sshguard
      '';
    };
  };
}
