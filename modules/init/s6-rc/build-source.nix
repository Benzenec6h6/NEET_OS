{
  lib,
  pkgs,
  services,
}:
with lib; let
  # log.enable (構造化) か logRun (生スクリプト) のどちらかがあればロガーを作る
  hasLog = svc: svc.type == "longrun" && (svc.log.enable || svc.logRun != null);

  # 構造化オプションから s6-log の run スクリプトを生成する。
  # run は root で起動されるので、ディレクトリ準備(root)→権限を落として s6-log、の順に行う。
  # s6-log は logdir 自体は作れるが、親ディレクトリの書き込み権限と所有者は面倒を見ないため、
  # ここで先に作って chown しておく。
  makeLoggerRun = name: svc: let
    inherit (svc) log;
    q = escapeShellArg;
    prepDir = d: ''
      ${pkgs.coreutils}/bin/mkdir -p ${q d}
      ${pkgs.coreutils}/bin/chown ${q log.user}: ${q d}
      ${pkgs.coreutils}/bin/chmod 0750 ${q d}
    '';
  in
    if svc.logRun != null
    then svc.logRun
    else ''
      #!${pkgs.runtimeShell}
      set -e
      ${concatMapStrings prepDir log.dirs}
      exec ${pkgs.s6}/bin/s6-setuidgid ${q log.user} \
        ${pkgs.s6}/bin/s6-log ${escapeShellArgs log.args}
    '';

  # 本体サービス
  makeServiceDir = name: svc: let
    files =
      {
        "type" = pkgs.writeText "${name}-type" svc.type;
      }
      // optionalAttrs (svc.dependencies != []) {
        "dependencies" = pkgs.writeText "${name}-dependencies" (concatStringsSep "\n" svc.dependencies);
      }
      // optionalAttrs (svc.type == "longrun") ({
          "run" = pkgs.writeScript "${name}-run" svc.run;
        }
        // optionalAttrs (svc.notification-fd != null) {
          "notification-fd" = pkgs.writeText "${name}-notification-fd" (toString svc.notification-fd);
        }
        // optionalAttrs (hasLog svc) {
          "producer-for" = pkgs.writeText "${name}-producer-for" "${name}-log";
        })
      // optionalAttrs (svc.type == "oneshot") {
        "up" =
          if svc.format == "sh"
          then pkgs.writeText "${name}-up" "${pkgs.writeShellScript "${name}-up.sh" svc.up}"
          else pkgs.writeText "${name}-up" svc.up;

        "down" =
          if svc.format == "sh" && svc.down != ""
          then pkgs.writeText "${name}-down" "${pkgs.writeShellScript "${name}-down.sh" svc.down}"
          else pkgs.writeText "${name}-down" svc.down;
      };
  in
    pkgs.linkFarm "${name}-srv-dir" (mapAttrsToList (filename: path: {
        name = filename;
        inherit path;
      })
      files);

  # ロガーサービス (<name>-log)
  # pipeline-name は top bundle に両方入れているため不要なので削除した
  makeLoggerDir = name: svc:
    pkgs.linkFarm "${name}-log-srv-dir" [
      {
        name = "type";
        path = pkgs.writeText "${name}-log-type" "longrun";
      }
      {
        name = "run";
        path = pkgs.writeScript "${name}-log-run" (makeLoggerRun name svc);
      }
      {
        name = "consumer-for";
        path = pkgs.writeText "${name}-log-consumer-for" name;
      }
    ];

  autoStartServices = filterAttrs (_: svc: svc.autoStart) services;
  autoStartLoggedServices = filterAttrs (_: hasLog) autoStartServices;

  loggedServices = filterAttrs (_: hasLog) services;

  serviceDirs =
    (mapAttrs makeServiceDir services)
    // (mapAttrs' (name: svc: nameValuePair "${name}-log" (makeLoggerDir name svc)) loggedServices)
    // {
      "top" = pkgs.linkFarm "top-bundle-dir" [
        {
          name = "type";
          path = pkgs.writeText "top-type" "bundle";
        }
        {
          name = "contents";
          path = pkgs.writeText "top-contents" (
            concatStringsSep "\n" (
              # ★ autoStartServices だけを top に入れる
              (attrNames autoStartServices)
              ++ (map (n: "${n}-log") (attrNames autoStartLoggedServices))
            )
          );
        }
      ];
    };
in
  pkgs.linkFarm "s6-rc-source" (mapAttrsToList (name: path: {inherit name path;}) serviceDirs)
