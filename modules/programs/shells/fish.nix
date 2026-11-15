{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.fish;

  # environment.variables を fish 向けの `set -gx` 文に変換
  fishSessionVars = lib.concatStringsSep "\n" (
    lib.mapAttrsToList (name: value: "set -gx ${name} ${lib.escapeShellArg value}") (
      lib.filterAttrs (_: value: value != null) config.environment.variables
    )
  );
in {
  options.programs.fish = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable fish.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.fish;
      defaultText = lib.literalExpression "pkgs.fish";
      description = "The package to use for fish.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.shells = [cfg.package];

    environment.etc."fish/config.fish".text = ''
      # /etc/fish/config.fish: system-wide fish config

      # システム PATH の登録
      fish_add_path -m /run/current-system/sw/bin /run/wrappers/bin

      # environment.variables の展開
      ${fishSessionVars}

      # 補完・関数の vendor パス追加
      set -p fish_complete_path /run/current-system/sw/share/fish/vendor_completions.d
      set -p fish_function_path /run/current-system/sw/share/fish/vendor_functions.d

      for file in /run/current-system/sw/share/fish/vendor_conf.d/*.fish
        if test -r $file
          source $file
        end
      end

      if status is-interactive
        eval (${pkgs.coreutils}/bin/dircolors -c)
        alias ls='ls --color=auto'
      end
    '';
  };
}
