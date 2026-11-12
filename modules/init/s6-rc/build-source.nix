{
  lib,
  pkgs,
  services,
}:
with lib; let
  hasLog = svc: svc.type == "longrun" && (svc.log.enable || svc.logRun != null);

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

  # 単純明快な run スクリプトの生成 (envdirs があれば s6-envdir を前置)
  makeRunScript = name: svc: let
    innerScript = pkgs.writeScript "${name}-run-inner" svc.run;
    envdirCmds = concatMapStrings (dir: "${pkgs.s6}/bin/s6-envdir -I ${escapeShellArg dir} ") svc.envdirs;
  in
    if svc.envdirs == []
    then pkgs.writeScript "${name}-run" svc.run
    else
      pkgs.writeScript "${name}-run" ''
        #!${pkgs.runtimeShell}
        exec ${envdirCmds}${innerScript} "$@"
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
          "run" = makeRunScript name svc;
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
      {
        name = "pipeline-name";
        path = pkgs.writeText "${name}-log-pipeline-name" "${name}-pipeline";
      }
    ];

  autoStartServices =
    filterAttrs (
      _: svc: svc.autoStart && svc.type == "longrun"
    )
    services;

  loggedServices = filterAttrs (_: hasLog) services;

  topContents =
    mapAttrsToList (
      name: svc:
        if hasLog svc
        then "${name}-pipeline"
        else name
    )
    autoStartServices;

  # partOf に指定された全バンドルを収集して contents をまとめる
  customBundles = let
    pairs = concatLists (mapAttrsToList (
        name: svc: let
          actualName =
            if hasLog svc
            then "${name}-pipeline"
            else name;
        in
          map (bundle: {
            inherit bundle;
            service = actualName;
          })
          svc.partOf
      )
      services);

    extractedBundles = zipAttrs (map (p: {"${p.bundle}" = p.service;}) pairs);
  in
    # ★ graphical-session は所属サービスが 0 個でも常に空バンドルとして存在を保証する
    extractedBundles
    // {
      "graphical-session" = extractedBundles."graphical-session" or [];
    };

  makeBundleDir = name: contents:
    pkgs.linkFarm "${name}-bundle-dir" [
      {
        name = "type";
        path = pkgs.writeText "${name}-type" "bundle";
      }
      {
        name = "contents";
        path = pkgs.writeText "${name}-contents" (concatStringsSep "\n" contents + "\n");
      }
    ];

  serviceDirs =
    (mapAttrs makeServiceDir services)
    // (mapAttrs' (name: svc: nameValuePair "${name}-log" (makeLoggerDir name svc)) loggedServices)
    // (mapAttrs makeBundleDir customBundles)
    // {
      "top" = makeBundleDir "top" topContents;
    };
in
  pkgs.linkFarm "s6-rc-source" (mapAttrsToList (name: path: {inherit name path;}) serviceDirs)
