{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    system.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
    };
    system.activationScript = lib.mkOption {
      type = lib.types.package;
      internal = true;
    };
    # 【追加】生成されたフックパッケージのリストを保持する
    system.activationHookPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      internal = true;
      default = [];
    };
  };

  config = let
    # 各フックを独立したパッケージにする
    hooks =
      lib.mapAttrs (
        name: text:
          pkgs.writeShellScript "hook-${name}" text
      )
      config.system.activationScripts;

    hookPaths = lib.attrValues hooks;
  in {
    system.activationHookPackages = hookPaths;

    system.activationScript = pkgs.writeScript "activate" ''
      #!${config.environment.execline}/bin/execlineb -P
      export PATH /bin

      if { mkdir -p /proc /sys /dev /etc /run /root /var/log /tmp }
      if { mount -t proc proc /proc }
      if { mount -t sysfs sysfs /sys }
      if { mount -t devtmpfs devtmpfs /dev }

      # 各フックを実行
      ${lib.concatStringsSep "\n" (map (path: "foreground { ${path} }") hookPaths)}

      # s6準備
      foreground { rm -rf /run/service }
      foreground { mkdir -p /run/service }
      # /etc/s6-scan の中身を /run/service にコピー
      # ※ etc-syncer が成功していればここにファイルがあるはず
      if { /bin/sh -c "test -d /etc/s6-scan" }
      /bin/sh -c "cp -rL /etc/s6-scan/. /run/service/"
    '';
  };
}
