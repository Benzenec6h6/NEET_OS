{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.networking.nftables;

  # テーブルごとの設定サブモジュール
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
      # ファイルパスか文字列のどちらでも渡せる
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
    # パッケージ導入
    environment.systemPackages = [cfg.package];

    # --- 提案されたサービス定義に置き換え ---
    system.s6-rc.services.nftables = {
      type = "oneshot";
      format = "sh";
      up = ''
        mkdir -p /var/lib/nftables
        [ -e ${state} ] || : > ${state}
        ${cfg.package}/bin/nft -f ${ruleset}
        cp ${deletions} ${state}
      '';
      down = ''
        ${cfg.package}/bin/nft -f ${state}
        : > ${state}
      '';
    };
  };
}
