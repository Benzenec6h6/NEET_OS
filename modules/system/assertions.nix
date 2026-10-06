{
  config,
  lib,
  ...
}: let
  failed = lib.filter (a: !a.assertion) config.assertions;

  # assertions が1つでも失敗していれば throw。警告があれば trace して value を返す
  checked = value:
    if failed != []
    then
      throw ''

        Failed assertions:
        ${lib.concatMapStringsSep "\n" (a: "- ${a.message}") failed}
      ''
    else lib.foldr (w: acc: builtins.trace "warning: ${w}" acc) value config.warnings;
in {
  options = {
    assertions = lib.mkOption {
      type = lib.types.listOf lib.types.unspecified;
      internal = true;
      default = [];
      description = "ビルドを止めるための検証。{ assertion, message } のリスト。";
    };

    warnings = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      internal = true;
      default = [];
      description = "ビルドは止めないが表示する警告。";
    };
  };

  # system.build は attrsOf raw なので、関数もそのまま入れられる（宣言は不要）
  config.system.build.checked = checked;
}
