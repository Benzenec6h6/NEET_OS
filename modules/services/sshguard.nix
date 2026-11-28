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

    system.stateDirectories = [
      {
        path = "/var/db/sshguard";
        mode = "0700";
        user = "root";
        group = "root";
      }
    ];

    system.s6-rc.services.sshguard = {
      type = "longrun";
      dependencies =
        optional config.services.openssh.enable "sshd"
        ++ optional config.services.syslog.enable "syslog"
        ++ optional (cfg.settings.BACKEND == "nft-sets") "nftables";

      run = ''
        #!/bin/sh
        export PATH="${makeBinPath [
          config.networking.nftables.package
          pkgs.coreutils
        ]}:$PATH"

        exec ${cfg.package}/bin/sshguard
      '';

      log = {
        enable = true;
        # デフォルトは ["n10" "s1000000" "T" "/var/log/sshguard"] ですが、
        # 元の指定（s500000）やタイムスタンプ（T）を反映したい場合は args で調整
        args = ["-b" "n10" "s500000" "T" "/var/log/sshguard"];
      };
    };
  };
}
