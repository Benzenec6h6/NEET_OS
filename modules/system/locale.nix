{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.locale;
in {
  options.locale = {
    defaultLocale = lib.mkOption {
      type = lib.types.str;
      default = "C.UTF-8";
      example = "ja_JP.UTF-8";
      description = "デフォルトロケール (LANG)。";
    };

    extraLocaleSettings = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = {};
      example = {
        LC_TIME = "ja_JP.UTF-8";
        LC_NUMERIC = "en_US.UTF-8";
      };
      description = "カテゴリごとの詳細なロケール設定 (LC_*)。";
    };
  };

  config = {
    # /etc/locale.conf の作成 (systemd でなくても、一部の GUI ツールや PAM が参照する標準仕様)
    environment.etc."locale.conf".text =
      lib.concatStringsSep "\n" (
        lib.mapAttrsToList (n: v: "${n}=${v}") (
          {LANG = cfg.defaultLocale;} // cfg.extraLocaleSettings
        )
      )
      + "\n";

    # environment.variables に流し込み、session-vars.sh を自動生成
    environment.variables =
      {
        LANG = cfg.defaultLocale;
        # glibc 向け: これがないと ja_JP.UTF-8 等に切り替えた際にロケール解決に失敗する
        LOCALE_ARCHIVE = "${pkgs.glibcLocales}/lib/locale/locale-archive";
      }
      // cfg.extraLocaleSettings;
  };
}
