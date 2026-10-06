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
    # 注意: system.build 配下には置かないこと。system.build は attrsOf raw なので、
    # どの system.build.* を読んでも全属性の定義値が WHNF まで評価される。
    # toplevel の定義が config.system.build.<何か> を必要とすると無限再帰になる。
    system.withAssertions = lib.mkOption {
      type = lib.types.unspecified;
      internal = true;
      readOnly = true;
      description = "値を assertions / warnings の検査を通してから返す関数。";
    };

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

  config.system.withAssertions = checked;
}
