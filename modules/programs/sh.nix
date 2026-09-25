{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.sh;

  # /bin/sh を指すシンボリックリンクを含んだパッケージを作る
  shPackage = pkgs.runCommand "bin-sh" {} ''
    mkdir -p $out/bin
    ln -s ${lib.getExe cfg.package} $out/bin/sh
  '';
in {
  options.programs.sh = {
    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.dash;
      defaultText = lib.literalExpression "pkgs.dash";
      description = ''
        Default shell linked system-wide to `/bin/sh`. Ensure any
        modifications to this shell are POSIX-compliant.
      '';
    };
  };

  config = {
    # これにより system.path/bin/sh が生成され、
    # bin_setup.rs が自動的に /bin/sh -> ... をリンクしてくれます
    environment.systemPackages = [
      cfg.package
      shPackage
    ];
  };
}
