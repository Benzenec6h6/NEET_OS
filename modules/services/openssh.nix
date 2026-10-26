{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.openssh;

  configFile = settingsFormat.generate "sshd.conf" cfg.settings;
  settingsFormat = let
    mkValueString = v:
      if lib.isInt v
      then toString v
      else if lib.isString v
      then v
      else if true == v
      then "yes"
      else if false == v
      then "no"
      else throw "unsupported type ${builtins.typeOf v}: ${(lib.generators.toPretty {}) v}";

    base = pkgs.formats.keyValue {
      listsAsDuplicateKeys = true;
      mkKeyValue = k: v: "${k} ${mkValueString v}";
    };

    commaSeparated = [
      "Ciphers"
      "KexAlgorithms"
      "Macs"
    ];
    spaceSeparated = [
      "AuthorizedKeysFile"
      "AllowGroups"
      "AllowUsers"
      "DenyGroups"
      "DenyUsers"
      "HostKey"
      "Port"
    ];
  in {
    inherit (base) type;

    generate = name: value: let
      transformedValue =
        lib.mapAttrs (
          key: val:
            if lib.isList val
            then
              if lib.elem key commaSeparated
              then lib.concatStringsSep "," (map toString val)
              else if lib.elem key spaceSeparated
              then lib.concatStringsSep " " (map toString val)
              else val
            else val
        )
        value;
    in
      base.generate name transformedValue;
  };
in {
  options.services.openssh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Whether to enable openssh as a system service.
      '';
    };

    startOnBoot = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to automatically start the SSH daemon on boot.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.openssh;
      defaultText = lib.literalExpression "pkgs.openssh";
      description = ''
        The package to use for `openssh`.
      '';
    };

    sftp = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether to enable the SFTP subsystem.
        '';
      };

      executable = lib.mkOption {
        type = lib.types.str;
        description = ''
          Path to the SFTP server executable.
        '';
      };

      flags = lib.mkOption {
        type = with lib.types; listOf str;
        default = [];
        description = ''
          Additional command-line flags to pass to the SFTP server.
        '';
      };
    };

    settings = lib.mkOption {
      type = lib.types.submodule {
        freeformType = settingsFormat.type;
        options = {
          AddressFamily = lib.mkOption {
            type = lib.types.enum ["any" "inet" "inet6"];
            default = "any";
          };

          Banner = lib.mkOption {
            type = lib.types.either (lib.types.enum ["none"]) lib.types.path;
            default = "none";
          };

          HostKey = lib.mkOption {
            type = with lib.types; listOf path;
            default = [];
          };

          LogLevel = lib.mkOption {
            type = lib.types.enum [
              "QUIET"
              "FATAL"
              "ERROR"
              "INFO"
              "VERBOSE"
              "DEBUG"
              "DEBUG1"
              "DEBUG2"
              "DEBUG3"
            ];
            default = "INFO";
          };

          UsePAM =
            lib.mkEnableOption "PAM authentication"
            // {
              default = true;
            };

          PasswordAuthentication = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };

          PermitRootLogin = lib.mkOption {
            default = "prohibit-password";
            type = lib.types.enum [
              "yes"
              "without-password"
              "prohibit-password"
              "forced-commands-only"
              "no"
            ];
          };

          ListenAddress = lib.mkOption {
            type = with lib.types; coercedTo str lib.singleton (listOf str);
            default = [];
          };

          Port = lib.mkOption {
            type = with lib.types; listOf port;
            default = [22];
          };

          KbdInteractiveAuthentication = lib.mkOption {
            type = lib.types.bool;
            default = cfg.settings.PasswordAuthentication;
          };

          KexAlgorithms = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "sntrup761x25519-sha512@openssh.com"
              "curve25519-sha256"
              "curve25519-sha256@libssh.org"
              "diffie-hellman-group-exchange-sha256"
            ];
          };

          Macs = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "hmac-sha2-512-etm@openssh.com"
              "hmac-sha2-256-etm@openssh.com"
              "umac-128-etm@openssh.com"
            ];
          };

          StrictModes = lib.mkOption {
            type = lib.types.bool;
            default = true;
          };

          Ciphers = lib.mkOption {
            type = with lib.types; listOf str;
            default = [
              "chacha20-poly1305@openssh.com"
              "aes256-gcm@openssh.com"
              "aes128-gcm@openssh.com"
              "aes256-ctr"
              "aes192-ctr"
              "aes128-ctr"
            ];
          };
        };
      };
      default = {};
    };
  };

  config = lib.mkIf cfg.enable {
    services.openssh.sftp.executable = lib.mkDefault "${cfg.package}/libexec/sftp-server";
    services.openssh.settings = {
      HostKey = ["/var/lib/sshd/ssh_host_ed25519_key"];
      "Subsystem sftp" =
        lib.mkIf cfg.sftp.enable "${cfg.sftp.executable} ${lib.concatStringsSep " " cfg.sftp.flags}";
    };

    # 設定ファイルの配置
    environment.etc."ssh/sshd_config".source = configFile;

    # パッケージ登録
    environment.systemPackages = [cfg.package];

    # 1. sshd グループの定義
    neet.gids.sshd = lib.mkDefault 998;

    system.stateDirectories = [
      # ホスト鍵を格納するディレクトリ（rootのみアクセス可）
      {
        path = "/var/lib/sshd";
        mode = "0700";
        user = "root";
        group = "root";
      }
      # 特権分離用（environment.nix にある場合は重複定義を避けるか、openssh側に統一）
      {
        path = "/var/empty";
        mode = "0755";
        user = "root";
        group = "root";
      }
    ];

    # 2. sshd ユーザーの定義
    neet.users.sshd = {
      uid = lib.mkDefault 998;
      gid = config.neet.gids.sshd;
      shell = "/bin/sh";
      home = "/var/empty";
      createHome = false;
      createRuntimeDir = false;
      description = "SSH privilege separation user";
    };

    # PAM 設定 (session_rundir は neet-os では静的解決されているため排除)
    neet.security.pam.services.sshd = lib.mkIf cfg.settings.UsePAM {
      text = let
        pam_unix = "${pkgs.pam}/lib/security/pam_unix.so";
        pam_deny = "${pkgs.pam}/lib/security/pam_deny.so";
        pam_env = "${pkgs.pam}/lib/security/pam_env.so";
      in ''
        # Account management
        account   required    ${pam_unix}

        # Authentication management
        auth      sufficient  ${pam_unix} nullok try_first_pass
        auth      required    ${pam_deny}

        # Password management
        password  sufficient  ${pam_unix} sha512 shadow nullok

        # Session management
        session   required    ${pam_env} conffile=/etc/security/pam_env.conf readenv=0
        session   required    ${pam_unix}
        ${
          lib.optionalString config.services.sessiond.enable
          "session   optional    ${config.services.sessiond.package}/lib/security/pam_sessiond.so"
        }
      '';
    };

    # --- s6-rc サービス定義 ---
    system.s6-rc.services = {
      # 1. ホスト鍵の生成 (oneshot)
      "sshd-prepare" = {
        type = "oneshot";
        format = "sh";
        autoStart = cfg.startOnBoot; # sshd と合わせる
        up = ''
          if ! [ -s "/var/lib/sshd/ssh_host_ed25519_key" ]; then
            ${cfg.package}/bin/ssh-keygen -t ed25519 -f "/var/lib/sshd/ssh_host_ed25519_key" -N ""
          fi
        '';
        down = "";
      };

      # 2. sshd デーモン本体 (longrun)
      "sshd" = {
        type = "longrun";
        autoStart = cfg.startOnBoot; # ★ ここで自動起動を制御
        dependencies = ["sshd-prepare" "syslog"];
        run = ''
          #!/bin/sh
          exec ${cfg.package}/bin/sshd -D -f /etc/ssh/sshd_config
        '';
        log.enable = true;
      };
    };
  };
}
