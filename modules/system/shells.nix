{
  config,
  pkgs,
  lib,
  ...
}: let
  atom = lib.types.oneOf [
    lib.types.int
    lib.types.str
    lib.types.path
  ];

  toStr = v:
    if lib.isPath v
    then "${v}"
    else toString v;
  toShellPath = x:
    if lib.isDerivation x
    then lib.getExe x
    else toString x;

  sessionVarsScript = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "export ${name}=${lib.escapeShellArg value}") (
      lib.filterAttrs (_: value: value != null) config.environment.variables
    )
  );

  allShells = lib.unique ((map toShellPath config.environment.shells) ++ ["/bin/sh"]);
in {
  options.environment.shells = lib.mkOption {
    type = with lib.types; listOf (oneOf [package path str]);
    default = [];
    description = "List of allowed login shells (/etc/shells).";
  };

  options.environment.variables = lib.mkOption {
    type = lib.types.attrsOf (
      lib.types.nullOr (lib.types.coercedTo atom lib.singleton (lib.types.listOf atom))
    );
    default = {};
    apply = lib.mapAttrs (
      _: value:
        if value == null
        then null
        else lib.concatMapStringsSep ":" toStr value
    );
    description = "Environment variables to export in /etc/profile.d/session-vars.sh";
  };

  config = {
    environment.etc."shells".text = ''
      ${lib.concatStringsSep "\n" allShells}
    '';

    environment.etc."profile".text = ''
      # /etc/profile: system-wide initialisation for POSIX login shells
      if [ -d /etc/profile.d ]; then
        for i in /etc/profile.d/*.sh; do
          [ -r "$i" ] && . "$i"
        done
        unset i
      fi
    '';

    environment.etc."profile.d/session-vars.sh" = lib.mkIf (config.environment.variables != {}) {
      text = sessionVarsScript;
    };
  };
}
