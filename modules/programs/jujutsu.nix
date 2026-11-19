{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.jujutsu;
  tomlFormat = pkgs.formats.toml {};

  userConfig = lib.filterAttrs (_: v: v != null) {
    name = cfg.userName;
    email = cfg.userEmail;
  };

  finalConfig =
    lib.recursiveUpdate
    (lib.optionalAttrs (userConfig != {}) {user = userConfig;})
    cfg.settings;
in {
  options.programs.jujutsu = {
    enable = lib.mkEnableOption "Jujutsu (jj) version control system";

    package = lib.mkPackageOption pkgs "jujutsu" {};

    userName = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default name to use for commits.";
    };

    userEmail = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Default email to use for commits.";
    };

    # Dynamic 補完専用の option
    enableDynamicCompletion = lib.mkOption {
      type = lib.types.bool;
      default = false; # またはお好みで true
      description = "Whether to enable dynamic shell completion (branches, revisions, etc.) for jujutsu in interactive shells.";
    };

    settings = lib.mkOption {
      type = tomlFormat.type;
      default = {};
      description = "Configuration written to /etc/jj/config.toml.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    environment.etc."jj/config.toml" = lib.mkIf (finalConfig != {}) {
      source = tomlFormat.generate "jj-config.toml" finalConfig;
    };

    # --- Dynamic 補完のシェル連携 ---
    # bash が有効かつ enableDynamicCompletion が有効な場合に追記
    programs.bash.interactiveShellInit = lib.mkIf (config.programs.bash.enable && cfg.enableDynamicCompletion) ''
      # jujutsu dynamic completion
      source <(COMPLETE=bash ${lib.getExe cfg.package})
    '';

    # zsh が有効かつ enableDynamicCompletion が有効な場合に追記
    programs.zsh.interactiveShellInit = lib.mkIf (config.programs.zsh.enable && cfg.enableDynamicCompletion) ''
      # jujutsu dynamic completion
      source <(COMPLETE=zsh ${lib.getExe cfg.package})
    '';
  };
}
