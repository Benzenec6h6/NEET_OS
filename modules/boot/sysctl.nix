{
  config,
  pkgs,
  lib,
  ...
}:
with lib; let
  cfg = config.boot.kernel.sysctl;

  # sysctl用の値の型（文字列、数値、真偽値、nullを許容）
  sysctlOption = mkOptionType {
    name = "sysctl option value";
    check = val: let
      checkType = x: isBool x || isString x || isInt x || x == null;
    in
      checkType val || (val._type or "" == "override" && checkType val.content);
    merge = loc: defs: mergeOneOption loc (filterOverrides defs);
  };

  # 複数箇所で設定された場合に「最大の数値」を採用する型
  highestValueType =
    types.ints.unsigned
    // {
      merge = loc: defs:
        foldl (a: b:
          if b.value == null
          then null
          else max a b.value)
        0 (filterOverrides defs);
    };
in {
  options.boot.kernel.sysctl = mkOption {
    type = types.submodule {
      freeformType = types.attrsOf sysctlOption;
      options = {
        "net.core.rmem_max" = mkOption {
          type = types.nullOr highestValueType;
          default = null;
          description = "The maximum receive socket buffer size in bytes.";
        };

        "net.core.wmem_max" = mkOption {
          type = types.nullOr highestValueType;
          default = null;
          description = "The maximum send socket buffer size in bytes.";
        };

        "vm.max_map_count" = mkOption {
          type = types.nullOr highestValueType;
          default = null;
          description = "The maximum number of memory map areas a process may have.";
        };
      };
    };
    default = {};
    description = ''
      Runtime parameters of the Linux kernel, as set by sysctl(8).
    '';
  };

  config = {
    # /etc/sysctl.d/ に設定ファイルを生成
    environment.etc."sysctl.d/60-default.conf".text = concatStrings (
      mapAttrsToList (
        n: v:
          optionalString (v != null) "${n}=${
            if v == false
            then "0"
            else toString v
          }\n"
      )
      cfg
    );

    # s6-rc の oneshot サービスとして起動時に適用
    system.s6-rc.services.sysctl = {
      type = "oneshot";
      up = ''
        ${pkgs.procps}/bin/sysctl -q --system
      '';
      down = "";
    };

    # セキュリティと互換性のためのデフォルト値
    boot.kernel.sysctl = {
      "kernel.kptr_restrict" = mkDefault 1;
      "vm.max_map_count" = mkDefault 1048576;
      "net.ipv4.ping_group_range" = mkDefault "0 2147483647";
    };
  };
}
