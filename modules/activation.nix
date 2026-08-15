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
      replacements = {
        modulesTree = "${config.system.modulesTree}";
        kmod = "${pkgs.pkgsStatic.kmod}";
      };
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
      export HOOK_PATHS="${lib.concatStringsSep " " hookPaths}"

      exec ${activationScriptFile}
    '';
  in {
    system.activationHookPackages = hookPaths;
    system.activationScript = activateRunner;
  };
}
