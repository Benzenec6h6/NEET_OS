{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.services.dhcpcd;

  # dhcpcd.conf 用の key-value フォーマッタ
  format = let
    format' = pkgs.formats.keyValue {
      listToValue = v: concatMapStringsSep "," toString v;
      mkKeyValue = k: v:
        if v == true
        then k
        else "${k} ${toString v}";
    };
  in {
    type = format'.type;
    generate = name: value: format'.generate name (filterAttrs (_: v: v != false) value);
  };
in {
  options.services.dhcpcd = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "dhcpcd をシステムサービスとして有効化するかどうか";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.dhcpcd.override {
        withUdev = false; # mdevd 環境なので udev プラグインを無効化する！
      };
      defaultText = literalExpression "pkgs.dhcpcd.override { withUdev = false; }";
      description = "使用する dhcpcd パッケージ";
    };

    debug = mkOption {
      type = types.bool;
      default = false;
      description = "デバッグログを有効化するかどうか";
    };

    extraArgs = mkOption {
      type = types.listOf types.str;
      default = [];
      description = "dhcpcd に渡す追加引数";
    };

    settings = mkOption {
      type = types.submodule {
        freeformType = format.type;
        options = {
          broadcast = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "ブロードキャストでリプライを返すよう要求";
          };
          duid = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "DHCP Unique Identifier (DUID) を使用";
          };
          ipv4only = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "IPv4 のみ設定";
          };
          ipv6only = mkOption {
            type = types.nullOr types.bool;
            default = null;
            description = "IPv6 のみ設定";
          };
        };
      };
      default = {};
      description = "dhcpcd.conf の設定";
    };

    configFile = mkOption {
      type = types.path;
      default = format.generate "dhcpcd.conf" (filterAttrs (_: v: v != null) cfg.settings);
      description = "生成された dhcpcd.conf";
    };
  };

  config = mkIf cfg.enable {
    services.dhcpcd.extraArgs = [
      "-B" # フォアグラウンドで実行（s6-rc longrun 必須）
      "-f"
      (toString cfg.configFile)
    ];

    services.dhcpcd.settings = {
      # DHCPサーバーに要求するオプション
      option = [
        "domain_name_servers"
        "domain_name"
        "domain_search"
        "host_name"
        "classless_static_routes"
        "ntp_servers"
        "interface_mtu"
      ];

      nohook = "lookup-hostname";

      # ループバックや仮想インターフェースは無視
      denyinterfaces = [
        "lo"
        "tap*"
        "tun*"
        "virbr*"
        "vnet*"
      ];

      debug = cfg.debug;
    };

    environment.systemPackages = [cfg.package];

    # s6-rc: longrun サービス
    system.s6-rc.services.dhcpcd = {
      type = "longrun";
      dependencies =
        optional config.services.mdevd.enable "mdevd-coldplug"
        ++ optional (config.system.s6-rc.services ? sysctl) "sysctl"
        ++ optional (config.system.s6-rc.services ? resolvconf) "resolvconf";

      run = ''
        #!/bin/sh
        # 1. DHCP に必須なカーネルモジュールを確実にロード
        ${pkgs.kmod}/bin/modprobe af_packet 2>/dev/null || ${pkgs.kmod}/bin/modprobe packet 2>/dev/null || true

        # 2. resolvconf へのパスを通す
        export PATH="${makeBinPath (optional config.programs.resolvconf.enable config.programs.resolvconf.package)}:$PATH"

        # 3. 余計な設定ファイルは一旦読ませず、フォアグラウンド(-B)で実行
        exec ${getExe cfg.package} -B
      '';
    };
  };
}
