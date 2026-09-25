{
  config,
  pkgs,
  lib,
  ...
}: let
  atom = lib.types.oneOf [
    lib.types.int
    lib.types.str
    lib.types.path
  ];

  toStr = v:
    if lib.isPath v
    then "${v}"
    else toString v;

  # パッケージなら実行ファイルのパス (lib.getExe) を、文字列やパスならそのまま文字列化
  toShellPath = x:
    if lib.isDerivation x
    then lib.getExe x
    else toString x;

  sessionVarsScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") (
      lib.filterAttrs (_: value: value != null) config.environment.variables
    )
  );

  # 重複を排除したシェルリスト
  allShells = lib.unique ((map toShellPath config.environment.shells) ++ ["/bin/sh"]);
in {
  options.environment.shells = lib.mkOption {
    # package, path, str のいずれも受け付けるように柔軟化
    type = with lib.types; listOf (oneOf [package path str]);
    default = [];
    description = "List of allowed login shells (/etc/shells).";
    example = lib.literalExpression "[ pkgs.bashInteractive \"/bin/sh\" ]";
  };

  options.environment.variables = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.nullOr (lib.types.coercedTo atom lib.singleton (lib.types.listOf atom))
    );
    default = {};
    apply = lib.mapAttrs (
      _: value:
        if value == null
        then null
        else lib.concatMapStringsSep ":" toStr value
    );
    description = "Environment variables to export in /etc/profile.d/session-vars.sh";
  };

  config = {
    # 1. 重複のないクリーンな /etc/shells を生成
    environment.etc."shells".text = ''
      ${lib.concatStringsSep "\n" allShells}
    '';

    # 2. 親となる /etc/profile は「profile.d を読み込むだけ」のシンプルな存在に徹する
    environment.etc."profile".text = ''
      # /etc/profile: system-wide initialisation for POSIX login shells
      if [ -d /etc/profile.d ]; then
        for i in /etc/profile.d/*.sh; do
          [ -r "$i" ] && . "$i"
        done
        unset i
      fi
    '';

    # 3. 定義された環境変数を session-vars.sh に書き出す
    environment.etc."profile.d/session-vars.sh" = lib.mkIf (config.environment.variables != {}) {
      text = sessionVarsScript;
    };
  };
}
