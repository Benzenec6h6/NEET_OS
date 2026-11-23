{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.networking.nftables;

  # --- 1. デフォルトルールセットの生成 (Stage 1 と同じパターン) ---
  tcpRule = optionalString (cfg.allowedTCPPorts != []) (
    "tcp dport { " + concatMapStringsSep ", " toString cfg.allowedTCPPorts + " } accept"
  );

  udpRule = optionalString (cfg.allowedUDPPorts != []) (
    "udp dport { " + concatMapStringsSep ", " toString cfg.allowedUDPPorts + " } accept"
  );

  # TCP と UDP のルールを結合（空行にならないよう調整）
  openPorts = concatStringsSep "\n  " (filter (s: s != "") [tcpRule udpRule]);

  defaultFilterFile = pkgs.replaceVarsWith {
    src = ./default-filter.nft;
    replacements = {
      inherit openPorts;
      extraInputRules = cfg.extraInputRules;
    };
  };

  # --- 2. テーブルごとの設定サブモジュール (既存の設計を維持) ---
  tableSubmodule = {name, ...}: {
    options = {
      enable = mkOption {
        type = types.bool;
        default = true;
      };
      name = mkOption {
        type = types.str;
        default = name;
        description = "テーブル名";
      };
      family = mkOption {
        type = types.enum ["ip" "ip6" "inet" "arp" "bridge" "netdev"];
        default = "inet";
        description = "アドレスファミリ";
      };
      contentFile = mkOption {
        type = types.nullOr types.path;
        default = null;
        description = "ルールが書かれた .nft ファイルのパス";
      };
      content = mkOption {
        type = types.lines;
        default = "";
        description = "ルール本文（文字列で直接書く場合）";
      };
    };
  };

  enabledTables = filterAttrs (_: t: t.enable) cfg.tables;

  state = "/var/lib/nftables/deletions.nft";

  # 有効なテーブルを削除するための nft スクリプト
  deletions = pkgs.writeText "nftables-deletions.nft" (
    concatStrings (mapAttrsToList (_: t: ''
        table ${t.family} ${t.name}
        delete table ${t.family} ${t.name}
      '')
      enabledTables)
  );

  # 実際に適用するルールセット
  ruleset = pkgs.writeText "nftables-ruleset.nft" ''
    include "${state}"
    include "${deletions}"
    ${concatStrings (mapAttrsToList (_: t: ''
        table ${t.family} ${t.name} {
          ${
          if t.contentFile != null
          then ''include "${t.contentFile}"''
          else t.content
        }
        }
      '')
      enabledTables)}
  '';
in {
  options.networking.nftables = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "Whether to enable nftables firewall.";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.nftables;
      description = "The nftables package to use.";
    };

    # --- 高レベルな簡易設定用オプション ---
    allowedTCPPorts = mkOption {
      type = types.listOf types.port;
      default = [];
      example = [22 80];
      description = "List of TCP ports to allow on default filter table.";
    };

    allowedUDPPorts = mkOption {
      type = types.listOf types.port;
      default = [];
      example = [53 51820];
      description = "List of UDP ports to allow on default filter table.";
    };

    extraInputRules = mkOption {
      type = types.lines;
      default = "";
      example = "iifname \"tailscale0\" accept";
      description = "Raw nftables rules to insert into the input chain of default filter table.";
    };

    # --- 低レベルなテーブル定義 (エスケープハッチ) ---
    tables = mkOption {
      type = types.attrsOf (types.submodule tableSubmodule);
      default = {};
      example = literalExpression ''
        {
          main-filter = {
            family = "inet";
            contentFile = ./rules.nft;
          };
        }
      '';
      description = "NEET_OSが管理するテーブルの集合";
    };
  };

  config = mkIf cfg.enable {
    # デフォルトの filter テーブルを mkDefault で流し込む
    # （ユーザーが独自に content / contentFile を指定した場合はそちらが優先される）
    networking.nftables.tables.filter = {
      family = mkDefault "inet";
      contentFile = mkDefault defaultFilterFile;
    };

    # パッケージ導入
    environment.systemPackages = [cfg.package];

    system.stateDirectories = [
      {
        path = "/var/lib/nftables";
        mode = "0700";
      }
    ];

    # --- サービス定義 (s6-rc) ---
    system.s6-rc.services.nftables = {
      type = "oneshot";
      format = "sh";
      up = ''
        [ -e "${state}" ] || : > "${state}"
        ${cfg.package}/bin/nft -f ${ruleset}
        ${pkgs.coreutils}/bin/cp -f ${deletions} ${state}
      '';
      down = ''
        ${cfg.package}/bin/nft -f ${state}
        : > "${state}"
      '';
    };
  };
}
