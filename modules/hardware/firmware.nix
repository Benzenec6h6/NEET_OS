{
  config,
  pkgs,
  lib,
  ...
}: {
  options = {
    hardware.firmware = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      # 実機向けにデフォルトで linux-firmware を入れておく
      default = [];
      defaultText = lib.literalExpression "[ pkgs.linux-firmware ]";
      description = ''
        カーネルが要求した際に自動ロードされるファームウェアパッケージのリスト。
      '';
      # リストされた複数のパッケージを 1 つのディレクトリツリーに束ねる
      apply = list:
        pkgs.buildEnv {
          name = "firmware";
          paths = list;
          pathsToLink = ["/lib/firmware"];
          ignoreCollisions = true;
        };
    };
  };
}
