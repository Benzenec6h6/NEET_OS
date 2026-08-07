{
  pkgs,
  lib,
  config,
  ...
}: {
  options.system.build = lib.mkOption {
    type = lib.types.attrsOf lib.types.anything;
    default = {};
    internal = true;
  };

  config.system.build.initrd = let
    rootPaths =
      [
        config.system.activationScript
        config.system.path
        config.system.etc.bin
      ]
      ++ config.system.activationHookPackages;

    closure = pkgs.closureInfo {inherit rootPaths;};

    initScript = pkgs.writeScript "init" ''
      #!${config.environment.execline}/bin/execlineb -P
      export PATH /bin
      foreground { ${config.system.activationScript} }
      exec s6-svscan /run/service
    '';

    manualInitrd =
      pkgs.runCommand "manual-initrd" {
        nativeBuildInputs = [pkgs.cpio pkgs.zstd];
      } ''
        # 作業用ディレクトリを作成
        mkdir root
        mkdir -p root/dev root/proc root/sys root/tmp root/run root/var/log

        # 1. closureInfo からファイルをコピー
        while read -r path; do
          mkdir -p "root/$(dirname "$path")"
          cp -a "$path" "root/$path"
        done < ${closure}/store-paths

        # 2. init と bin の配置
        cp ${initScript} root/init
        chmod +x root/init
        mkdir -p root/bin
        ln -s ${config.system.path}/bin/* root/bin/

        # 3. 【ここを修正】 $out をディレクトリにし、その中に initrd ファイルを作成する
        mkdir -p $out
        (cd root && find . -print0 | cpio --null -o -H newc --quiet | zstd -z > $out/initrd)
      '';
  in
    manualInitrd;
}
