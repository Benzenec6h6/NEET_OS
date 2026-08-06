{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
    };
    system.path = lib.mkOption {
      internal = true;
      type = lib.types.path;
    };
  };

  config = {
    system.path = pkgs.buildEnv {
      name = "system-path";
      paths = config.environment.systemPackages;
      # /bin を含めるように明示
      pathsToLink = ["/bin"];
      ignoreCollisions = true;
      postBuild = ''
        if [ -x $out/bin/busybox ]; then
          $out/bin/busybox --install -s $out/bin
        fi
      '';
    };

    environment.etc."os-release".text = ''
      NAME="NEET OS"
      ID=neet-os
      PRETTY_NAME="NEET OS v0.1"
    '';

    # /etc/profile を強化
    environment.etc."profile".text = ''
      export PATH=/bin:/sbin
      export TERM=linux
      export PS1='\e[1;32mNEET-OS\e[0m \w \$ '
    '';
  };
}
