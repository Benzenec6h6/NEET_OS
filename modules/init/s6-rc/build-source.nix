{
  lib,
  pkgs,
  services,
}:
with lib; let
  # 個別のサービスディレクトリを作成する関数
  makeServiceDir = name: svc: let
    files =
      {
        "type" = pkgs.writeText "${name}-type" svc.type;
      }
      // optionalAttrs (svc.dependencies != []) {
        "dependencies" = pkgs.writeText "${name}-dependencies" (concatStringsSep "\n" svc.dependencies);
      }
      // optionalAttrs (svc.type == "longrun") ({
          "run" = pkgs.writeText "${name}-run" svc.run;
        }
        // optionalAttrs (svc.notification-fd != null) {
          "notification-fd" = pkgs.writeText "${name}-notification-fd" (toString svc.notification-fd);
        })
      // optionalAttrs (svc.type == "oneshot") {
        "up" = pkgs.writeText "${name}-up" svc.up;
        "down" = pkgs.writeText "${name}-down" svc.down;
      };
  in
    pkgs.linkFarm "${name}-srv-dir" (mapAttrsToList (filename: path: {
        name = filename;
        inherit path;
      })
      files);

  # 定義された全サービス＋"top"バンドル
  serviceDirs =
    (mapAttrs makeServiceDir services)
    // {
      "top" = pkgs.linkFarm "top-bundle-dir" [
        {
          name = "type";
          path = pkgs.writeText "top-type" "bundle";
        }
        {
          name = "contents";
          path = pkgs.writeText "top-contents" (concatStringsSep "\n" (attrNames services));
        }
      ];
    };
in
  # 全サービスのディレクトリンクをまとめた1つのソースディレクトリ
  pkgs.linkFarm "s6-rc-source" (mapAttrsToList (name: path: {inherit name path;}) serviceDirs)
