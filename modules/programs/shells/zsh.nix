{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.zsh;
in {
  options.programs.zsh = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable zsh.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.zsh;
      defaultText = lib.literalExpression "pkgs.zsh";
      description = "The package to use for zsh.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];
    environment.shells = [cfg.package];

    # ログイン時に /etc/profile (/etc/profile.d/session-vars.sh 等) を読み込む
    environment.etc."zprofile".text = ''
      if [ -r /etc/profile ]; then
        emulate sh -c '. /etc/profile'
      fi
    '';

    environment.etc."zshrc".text = ''
      # /etc/zshrc: system-wide interactive zsh config
      fpath=(
        /run/current-system/sw/share/zsh/site-functions
        /run/current-system/sw/share/zsh/$ZSH_VERSION/functions
        $fpath
      )

      autoload -Uz compinit
      compinit -u

      autoload -Uz promptinit
      promptinit
      PROMPT='%F{green}[%n@%m:%~]%#%f '

      HISTSIZE=10000
      SAVEHIST=10000
      setopt HIST_IGNORE_DUPS
      setopt SHARE_HISTORY

      eval "$(${pkgs.coreutils}/bin/dircolors -b)"
      alias ls='ls --color=auto'
    '';
  };
}
