{
  config,
  pkgs,
  lib,
  ...
}: let
  zeroPad = width: value: let
    s = toString value;
    padding = lib.concatStrings (builtins.genList (_: "0") (width - builtins.stringLength s));
  in
    padding + s;

  mkHook = mode: k: v: let
    name = "zzz.d/${zeroPad 4 v.priority}-${k}.sh";
    script = pkgs.writeShellScript k ''
      [ "''${ZZZ_MODE:-}" = "${mode}" ] || exit 0
      [ "$1" = "pre" ] || exit 0
      ${v.action}
    '';
  in
    lib.nameValuePair name {source = script;};

  mkResumeHook = k: v: let
    name = "zzz.d/${zeroPad 4 v.priority}-${k}.sh";
    script = pkgs.writeShellScript k ''
      [ "$1" = "post" ] || exit 0
      ${v.action}
    '';
  in
    lib.nameValuePair name {source = script;};

  hookOpts = {name, ...}: {
    options = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "フックを有効にするかどうか";
      };
      event = lib.mkOption {
        type = lib.types.enum ["suspend" "hibernate" "resume"];
        description = "トリガーとなるイベント";
      };
      action = lib.mkOption {
        type = lib.types.lines;
        description = "実行するシェルスクリプト";
      };
      priority = lib.mkOption {
        type = lib.types.int;
        default = 500;
        description = "実行順序の優先度 (数値が小さいほど先に実行)";
      };
    };
  };
in {
  options.providers.resumeAndSuspend = {
    backend = lib.mkOption {
      type = lib.types.enum ["none" "zzz"];
      default = "none";
      description = "使用するサスペンド/レジュームバックエンド";
    };

    hooks = lib.mkOption {
      type = lib.types.attrsOf (lib.types.submodule hookOpts);
      default = {};
      description = "サスペンド/復帰時に実行するフック";
    };
  };

  config = lib.mkIf (config.providers.resumeAndSuspend.backend == "zzz") {
    environment.etc = let
      filtered = event: lib.filterAttrs (_: v: v.enable && v.event == event) config.providers.resumeAndSuspend.hooks;

      suspend = lib.mapAttrs' (k: v: mkHook "suspend" k v) (filtered "suspend");
      hibernate = lib.mapAttrs' (k: v: mkHook "hibernate" k v) (filtered "hibernate");
      resume = lib.mapAttrs' (k: v: mkResumeHook k v) (filtered "resume");
    in
      lib.mkMerge [
        suspend
        hibernate
        resume
      ];
  };
}
