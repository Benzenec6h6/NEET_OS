{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.programs.resolvconf;

  listToValue = concatMapStringsSep " " (generators.mkValueStringDefault {});

  # resolvconf.conf 用の key-value フォーマッタ
  format =
    (pkgs.formats.keyValue {inherit listToValue;})
    // {
      generate = name: value: let
        transformedValue =
          mapAttrs (
            key: val:
              if isList val
              then "'" + listToValue val + "'"
              else if isBool val
              then boolToString val
              else toString val
          )
          value;
      in
        pkgs.writeText name (generators.toKeyValue {} transformedValue);
    };
in {
  options.programs.resolvconf = {
    enable = mkOption {
      type = types.bool;
      default = false;
      description = "openresolv による /etc/resolv.conf の自動調停を有効化するかどうか";
    };

    package = mkOption {
      type = types.package;
      default = pkgs.openresolv.overrideAttrs (_: {
        configurePhase = ''
          cat > config.mk <<EOF
          PREFIX=$out
          SYSCONFDIR=/etc
          SBINDIR=$out/sbin
          LIBEXECDIR=$out/libexec/resolvconf
          VARDIR=/run/resolvconf
          MANDIR=$out/share/man
          RESTARTCMD=""
          EOF
        '';
      });
      defaultText = literalExpression "pkgs.openresolv";
      description = "使用する openresolv パッケージ";
    };

    settings = mkOption {
      type = format.type;
      default = {};
      description = "resolvconf.conf の設定（詳細は resolvconf.conf(5) を参照）";
    };
  };

  config = mkIf cfg.enable {
    # デフォルトの resolvconf 設定
    programs.resolvconf.settings = {
      interface_order = [
        "lo"
        "lo[0-9]"
      ];
      resolv_conf = "/etc/resolv.conf";
    };

    # /etc/resolvconf.conf の生成
    environment.etc."resolvconf.conf".source = format.generate "resolvconf.conf" cfg.settings;

    # resolvconf コマンドをシステムで使えるようにする
    # （後で iwd や dhcpcd から呼び出せるようになります）
    environment.systemPackages = [cfg.package];

    # s6-rc: 起動時に resolvconf -u を叩いて初期状態を反映する oneshot サービス
    system.s6-rc.services.resolvconf = {
      type = "oneshot";
      up = "${getExe cfg.package} -u";
      down = "";
    };
  };
}
