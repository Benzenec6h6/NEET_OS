{
  pkgs,
  lib,
  config,
  ...
}: let
  # rebuild スクリプトをパッケージ化
  neetRebuild = pkgs.writeShellScriptBin "neet-rebuild" (builtins.readFile ./rebuild.sh);
in {
  options = {
    environment.systemPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
    };
    environment.execline = lib.mkOption {
      type = lib.types.package;
      default = pkgs.execline;
      description = ''
        execline package. /bin/execlineb from this package is relied upon,
        by literal absolute path, as the interpreter for PID 1's init script
        and the system activation script.
      '';
    };
    system.path = lib.mkOption {
      internal = true;
      type = lib.types.path;
    };
  };

  config = {
    # ★ neetRebuild を追加
    environment.systemPackages = [
      config.environment.execline
      neetRebuild
      pkgs.util-linux
    ];

    system.path = pkgs.buildEnv {
      name = "system-path";
      paths =
        config.environment.systemPackages
        ++ lib.optionals (config.hardware.graphics.enable or false) [
          (pkgs.runCommand "graphics-drivers-syspath" {} ''
            mkdir -p $out
            ln -s ${config.system.build.graphicsDrivers} $out/graphics-drivers
            ${lib.optionalString (config.hardware.graphics.enable32Bit or false) ''
              ln -s ${config.system.build.graphicsDrivers32} $out/graphics-drivers-32bit
            ''}
          '')
        ];
      pathsToLink = [
        "/bin"
        "/graphics-drivers"
        "/graphics-drivers-32bit"
      ];
      ignoreCollisions = true;
    };

    environment.etc."os-release".text = ''
      NAME="NEET OS"
      ID=neet-os
      PRETTY_NAME="NEET OS v0.1"
    '';

    # /etc/profile を強化 (環境変数の一元化)
    environment.etc."profile".text = ''
      export HOME=''${HOME:-/root}
      export PATH=/run/wrappers/bin:/run/current-system/bin:/bin:/sbin
      export TERM=linux
      export PS1='\e[1;32mNEET-OS\e[0m \w \$ '

      # Nix 関連
      export NIX_REMOTE=daemon
      export SSL_CERT_FILE=/etc/ssl/certs/ca-certificates.crt
      export CURL_CA_BUNDLE=/etc/ssl/certs/ca-certificates.crt
    '';
  };
}
