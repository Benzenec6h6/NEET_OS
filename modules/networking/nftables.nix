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

  # Rust に渡すためのマニフェストデータ
  # 各テーブルのルールファイルパスを確定させてJSON化する
  manifest = {
    tables =
      mapAttrsToList (_: t: let
        ruleFile =
          if t.contentFile != null
          then t.contentFile
          else
            pkgs.writeText "${t.family}-${t.name}.nft" ''
              table ${t.family} ${t.name} {
                ${t.content}
              }
            '';
      in {
        name = t.name;
        family = t.family;
        path = "${ruleFile}";
      })
      enabledTables;
  };

  manifestJson = (pkgs.formats.json {}).generate "nftables-manifest.json" manifest;
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
    # 1. パッケージ導入
    environment.systemPackages = [cfg.package];

    # 2. Rust 用のマニフェストを配置
    environment.etc."nftables/manifest.json".source = manifestJson;

    # 3. s6-rc: 反映を行う oneshot サービス
    system.s6-rc.services.nftables = {
      type = "oneshot";
      format = "sh";
      up = ''
        /bin/system-init firewall
      '';
      down = ''
        # サービス停止時はルールをクリア（必要に応じて）
        ${cfg.package}/bin/nft flush ruleset
      '';
    };
  };
}
