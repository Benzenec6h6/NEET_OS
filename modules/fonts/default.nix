{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.fonts;

  # インストール対象のフォントパッケージ一覧
  fontDirs = cfg.packages;

  # 64bit用キャッシュ（ビルド時に事前生成）
  cache64 = pkgs.makeFontsCache {
    fontconfig = pkgs.fontconfig;
    fontDirectories = fontDirs;
  };

  # 32bit (i686) 用キャッシュ（Steam / Wine 対策）
  cache32 = pkgs.makeFontsCache {
    fontconfig = pkgs.pkgsi686Linux.fontconfig;
    fontDirectories = fontDirs;
  };

  # 最小限の default-fonts XML
  # sans-serif / monospace / emoji のフォールバック順を定義
  defaultFontsConf = pkgs.writeText "50-neet-default-fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <alias binding="same">
        <family>sans-serif</family>
        <prefer>
          ${lib.concatMapStringsSep "\n" (f: "<family>${f}</family>") cfg.defaultFonts.sansSerif}
        </prefer>
      </alias>
      <alias binding="same">
        <family>monospace</family>
        <prefer>
          ${lib.concatMapStringsSep "\n" (f: "<family>${f}</family>") cfg.defaultFonts.monospace}
        </prefer>
      </alias>
      <alias binding="same">
        <family>emoji</family>
        <prefer>
          ${lib.concatMapStringsSep "\n" (f: "<family>${f}</family>") cfg.defaultFonts.emoji}
        </prefer>
      </alias>
    </fontconfig>
  '';

  # /etc/fonts/fonts.conf 本体の生成
  fontsConf = pkgs.writeText "fonts.conf" ''
    <?xml version="1.0"?>
    <!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
    <fontconfig>
      <!-- システムにインストールされたフォントのパス -->
      ${lib.concatMapStringsSep "\n" (p: "<dir>${p}</dir>") fontDirs}

      <!-- 事前生成キャッシュのパス (64bit & 32bit) -->
      <cachedir>${cache64}</cachedir>
      <cachedir>${cache32}</cachedir>
      <cachedir>~/.cache/fontconfig</cachedir>

      <!-- Upstream の標準ルールを読み込む -->
      <include>${pkgs.fontconfig.out}/etc/fonts/conf.d</include>

      <!-- ビットマップフォントの排除 (upstream の 70-no-bitmaps を適用) -->
      <include>${pkgs.fontconfig.out}/share/fontconfig/conf.avail/70-no-bitmaps.conf</include>

      <!-- MS系フォント等に埋め込まれたビットマップを無視し、常に綺麗にアンチエイリアス描画する -->
      <match target="font">
        <edit name="embeddedbitmap" mode="assign">
          <bool>false</bool>
        </edit>
      </match>

      <!-- 独自デフォルトフォント定義 -->
      <include>${defaultFontsConf}</include>

      <!-- Arial や MS Gothic を要求されたときの代替 (Wine/Steamゲーム対策) -->
      <match target="pattern">
        <test name="family"><string>Arial</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Liberation Sans</string></edit>
      </match>
      <match target="pattern">
        <test name="family"><string>MS Gothic</string></test>
        <edit name="family" mode="assign" binding="strong"><string>Noto Sans CJK JP</string></edit>
      </match>
    </fontconfig>
  '';
in {
  options.fonts = {
    enable = lib.mkEnableOption "Fontconfig and system fonts support";

    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        noto-fonts
        noto-fonts-cjk-sans
        noto-fonts-color-emoji
        liberation_fonts # Arial / Times 互換（Wine/Steam対策で追加）
        vlgothic
      ];
      description = "List of font packages to install.";
    };

    defaultFonts = {
      sansSerif = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["Noto Sans CJK JP" "Noto Sans"];
      };
      monospace = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["Noto Sans Mono CJK JP" "DejaVu Sans Mono"];
      };
      emoji = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = ["Noto Color Emoji"];
      };
    };
  };

  config = lib.mkIf cfg.enable {
    # NEET_OS の etc 管理機能（etc.nix / system-init）に渡す
    environment.etc."fonts/fonts.conf".source = fontsConf;

    # アプリ側が参照するための環境変数（environment.nix へ流す）
    environment.variables = {
      FONTCONFIG_FILE = "/etc/fonts/fonts.conf";
    };

    # fc-list や fc-match などのデバッグ用CLIツール
    environment.systemPackages = [pkgs.fontconfig];
  };
}
