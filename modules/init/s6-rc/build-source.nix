{
  lib,
  pkgs,
  s6lib,
  services,
}:
with lib; let
  inherit (s6lib) hasLog loggerName pipelineName entryName;

  # ---- 小さなビルダー ----
  # { ファイル名 = パス; } -> linkFarm
  mkFarm = name: files:
    pkgs.linkFarm name (mapAttrsToList (n: path: {
        name = n;
        inherit path;
      })
      files);

  txt = name: key: pkgs.writeText "${name}-${key}";

  # oneshot の up/down: sh 形式なら writeShellScript のパスを書く
  mkOneshotScript = name: svc: key: body:
    if svc.format == "sh" && body != ""
    then txt name key "${pkgs.writeShellScript "${name}-${key}.sh" body}"
    else txt name key body;

  # envdirs があれば s6-envdir を前置した run
  mkRunScript = name: svc:
    if svc.envdirs == []
    then pkgs.writeScript "${name}-run" svc.run
    else let
      inner = pkgs.writeScript "${name}-run-inner" svc.run;
      envdirCmds = concatMapStrings (d: "${pkgs.s6}/bin/s6-envdir -I ${escapeShellArg d} ") svc.envdirs;
    in
      pkgs.writeScript "${name}-run" ''
        #!${pkgs.runtimeShell}
        exec ${envdirCmds}${inner} "$@"
      '';

  mkLoggerRun = svc: let
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

  # ---- 各ディレクトリ ----
  mkServiceDir = name: svc:
    mkFarm "${name}-srv-dir" (
      {type = txt name "type" svc.type;}
      // optionalAttrs (svc.dependencies != []) {
        dependencies = txt name "dependencies" (concatStringsSep "\n" svc.dependencies);
      }
      // optionalAttrs (svc.type == "longrun") (
        {run = mkRunScript name svc;}
        // optionalAttrs (svc.notification-fd != null) {
          notification-fd = txt name "notification-fd" (toString svc.notification-fd);
        }
        // optionalAttrs (hasLog svc) {
          producer-for = txt name "producer-for" (loggerName name);
        }
      )
      // optionalAttrs (svc.type == "oneshot") {
        up = mkOneshotScript name svc "up" svc.up;
        down = mkOneshotScript name svc "down" svc.down;
      }
    );

  mkLoggerDir = name: svc: let
    lname = loggerName name;
  in
    mkFarm "${lname}-srv-dir" {
      type = txt lname "type" "longrun";
      run = pkgs.writeScript "${lname}-run" (mkLoggerRun svc);
      consumer-for = txt lname "consumer-for" name;
      pipeline-name = txt lname "pipeline-name" (pipelineName name);
    };

  mkBundleDir = name: contents:
    mkFarm "${name}-bundle-dir" {
      type = txt name "type" "bundle";
      contents = txt name "contents" (
        concatStringsSep "\n" contents + optionalString (contents != []) "\n"
      );
    };

  # ---- バンドル ----
  # type = "bundle" で宣言された contents と、各サービスの partOf を統合して全バンドルを作る。
  resolveEntry = n:
    if services ? ${n}
    then entryName n services.${n}
    else n;

  realServices = filterAttrs (_: s: s.type != "bundle") services;

  declaredBundles =
    mapAttrs (_: svc: map resolveEntry svc.contents)
    (filterAttrs (_: s: s.type == "bundle") services);

  partOfPairs = concatLists (mapAttrsToList (
      name: svc: map (bundle: {${bundle} = entryName name svc;}) svc.partOf
    )
    services);

  bundles = zipAttrsWith (_: xs: unique (concatLists xs)) [
    declaredBundles
    (zipAttrs partOfPairs)
  ];

  topContents = mapAttrsToList entryName (filterAttrs (_: svc: svc.autoStart) services);

  serviceDirs =
    mapAttrs mkServiceDir realServices
    // mapAttrs' (name: svc: nameValuePair (loggerName name) (mkLoggerDir name svc)) (filterAttrs (_: hasLog) realServices)
    // mapAttrs mkBundleDir bundles
    // {top = mkBundleDir "top" topContents;};
in
  mkFarm "s6-rc-source" serviceDirs
