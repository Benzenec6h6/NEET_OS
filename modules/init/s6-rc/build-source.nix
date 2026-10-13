{
  lib,
  pkgs,
  services,
}:
with lib; let
  hasLog = svc: svc.type == "longrun" && svc.logRun != null;

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
  makeLoggerDir = name: svc:
    pkgs.linkFarm "${name}-log-srv-dir" [
      {
        name = "type";
        path = pkgs.writeText "${name}-log-type" "longrun";
      }
      {
        name = "run";
        path = pkgs.writeScript "${name}-log-run" svc.logRun;
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
              (attrNames services)
              ++ (map (n: "${n}-log") (attrNames loggedServices))
            )
          );
        }
      ];
    };
in
  pkgs.linkFarm "s6-rc-source" (mapAttrsToList (name: path: {inherit name path;}) serviceDirs)
