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
    system.activationHookPackages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      internal = true;
      default = [];
    };
  };

  config = let
    activationScriptFile = pkgs.replaceVarsWith {
      src = ./activation.sh;
      replacements = {};
      isExecutable = true;
    };
    hooks =
      lib.mapAttrs (
        name: text:
          pkgs.writeShellScript "hook-${name}" text
      )
      config.system.activationScripts;

    hookPaths = lib.attrValues hooks;

    # activate.sh をラッパー経由で呼ぶ実行可能パッケージにする
    activateRunner = pkgs.writeShellScript "activate" ''
      export SYSTEM_PATH="${config.system.path}"
      export EXTRA_BIN_PATH="${pkgs.coreutils}/bin:${pkgs.busybox}/bin"
      export HOOK_PATHS="${lib.concatStringsSep " " hookPaths}"

      exec ${activationScriptFile}
    '';
  in {
    system.activationHookPackages = hookPaths;
    system.activationScript = activateRunner;
  };
}
