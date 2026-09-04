{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.security.wrappers;

  # 個々の Wrapper の型定義
  wrapperOpts = types.submodule {
    options = {
      source = mkOption {
        type = types.path;
        description = "ラッパー対象となるオリジナルの実行ファイルパス (例: \${pkgs.sudo-rs}/bin/sudo)";
      };
      setuid = mkOption {
        type = types.bool;
        default = false;
        description = "Setuid(root) ビットを付与するかどうか";
      };
      setgid = mkOption {
        type = types.bool;
        default = false;
        description = "Setgid ビットを付与するかどうか";
      };
      owner = mkOption {
        type = types.str;
        default = "root";
        description = "バイナリの所有者";
      };
      group = mkOption {
        type = types.str;
        default = "root";
        description = "バイナリの所有グループ";
      };
      capabilities = mkOption {
        type = types.listOf types.str;
        default = [];
        example = ["cap_net_raw+ep" "cap_net_bind_service+ep"];
        description = "付与する Linux Capabilities (Ambient Capabilities)";
      };
    };
  };

  # Rust(etc_syncer / system-init) 側へ渡す JSON 構造への変換処理
  # wrappers.json の各エントリーをマップ
  wrappersJsonData =
    mapAttrsToList (name: w: {
      program = name; # /run/wrappers/bin/<program> となる名前
      source = toString w.source; # Nix store 上のオリジナルバイナリパス
      setuid = w.setuid;
      setgid = w.setgid;
      owner = w.owner;
      group = w.group;
      capabilities = w.capabilities;
    })
    cfg;
in {
  options.neet.security.wrappers = mkOption {
    type = types.attrsOf wrapperOpts;
    default = {};
    example = literalExpression ''
      {
        sudo = {
          source = "\${pkgs.sudo-rs}/bin/sudo";
          setuid = true;
          owner = "root";
          group = "root";
        };
        ping = {
          source = "\${pkgs.iputils}/bin/ping";
          capabilities = [ "cap_net_raw+ep" ];
        };
      }
    '';
    description = "/run/wrappers/bin に配置する Setuid / Capability ラッパーの定義";
  };

  config = mkIf (cfg != {}) {
    # Rust 側がパースするための設定ファイルを出力
    environment.etc."wrappers.json".text = builtins.toJSON wrappersJsonData;
  };
}
