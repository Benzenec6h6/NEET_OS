{lib, ...}: {
  isUser ? false,
  username ? null,
  home ? (
    if username != null
    then "/home/${username}"
    else null
  ),
}:
with lib;
  {name, ...}: let
    # 確実に文字列としてホームディレクトリを解決
    resolvedHome =
      if home != null
      then home
      else if username != null
      then "/home/${username}"
      else "/var/empty";
  in {
    options = {
      type = mkOption {type = types.enum ["longrun" "oneshot" "bundle"];};
      run = mkOption {
        type = types.lines;
        default = "";
      };
      up = mkOption {
        type = types.lines;
        default = "";
      };
      down = mkOption {
        type = types.lines;
        default = "";
      };
      dependencies = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      notification-fd = mkOption {
        type = types.nullOr types.int;
        default = null;
      };
      format = mkOption {
        type = types.enum ["execline" "sh"];
        default = "execline";
        description = "oneshot スクリプトの記述言語 (execline または sh)";
      };
      autoStart = mkOption {
        type = types.bool;
        default = true;
        description = "ブート時/セッション開始時に自動起動する (top bundle に含める) かどうか";
      };
      contents = mkOption {
        type = types.listOf types.str;
        default = [];
        description = ''
          type = "bundle" のときのメンバー(サービス名。ログ付きなら元の名前でよい)。
          バンドル側がメンバーを決める場合に使う。メンバー側から参加させたい場合は partOf を使う。
        '';
      };
      partOf = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "このサービスを所属させるバンドル一覧。メンバーが分散するもの (例: graphical-session) 向け。";
      };

      envdirs = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "起動前に s6-envdir で読み込む環境変数ディレクトリ一覧";
      };

      loadSecrets = mkOption {
        type = types.bool;
        default = false;
        description = "シークレット復号サービスへの依存と読み込みを自動化";
      };

      log = {
        enable = mkEnableOption "s6-log によるロガーの自動生成";
        user = mkOption {
          type = types.str;
          default =
            if isUser
            then username
            else "s6log";
          description = "s6-log を実行するユーザー";
        };
        dirs = mkOption {
          type = types.listOf types.str;
          default =
            if isUser
            then ["${resolvedHome}/.local/state/log/${name}"]
            else ["/var/log/${name}"];
          description = "事前に作成するログディレクトリ";
        };
        args = mkOption {
          type = types.listOf types.str;
          default = let
            logDir =
              if isUser
              then "${resolvedHome}/.local/state/log/${name}"
              else "/var/log/${name}";
          in ["n10" "s1000000" "T" logDir];
          description = "s6-log に渡す引数";
        };
      };

      logRun = mkOption {
        type = types.nullOr types.lines;
        default = null;
        description = "ロガーの run スクリプトを丸ごと上書きする";
      };
    };
  }
