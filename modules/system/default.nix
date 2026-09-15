{
  config,
  pkgs,
  lib,
  ...
}: let
  # modules/init/ から提供される stage2Init (本番の /init) を参照
  stage2Init = config.system.build.stage2Init;

  # OS全体の最終成果物 (ルートファイルシステムに展開される核)
  toplevel =
    pkgs.runCommand "neet-os-toplevel" {
      passthru = {
        inherit stage2Init;
        systemPath = config.system.path;
        etc = config.system.etc.package;
      };
    } ''
      mkdir -p $out
      ln -s ${stage2Init} $out/init
      ln -s ${config.system.path} $out/system-path
      ln -s ${config.system.etc.package} $out/etc
    '';
in {
  imports = [
    ./etc
    ./users.nix
    ./environment.nix
  ];

  options = {
    # 各モジュールがカーネルやスクリプトなどの成果物を登録する共通のスロット
    system.build = lib.mkOption {
      type = lib.types.attrsOf lib.types.raw;
      default = {};
      description = "システム全体のビルド成果物を格納する属性セット";
    };
  };

  config = {
    # 最終的な OS toplevel を公開
    system.build.toplevel = toplevel;
  };
}
