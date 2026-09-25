{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.programs.bash;
in {
  options.programs.bash = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to enable bash.";
    };

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.bashInteractive;
      defaultText = lib.literalExpression "pkgs.bashInteractive";
      description = "The package to use for bash.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [cfg.package];

    # /etc/profile.d/bash.sh を配置
    environment.etc."profile.d/bash.sh".text = ''
      if [ -n "''${BASH_VERSION:-}" ] && [ -r /etc/bashrc ]; then
        . /etc/bashrc
      fi
    '';

    environment.etc."bashrc".text = ''
      # /etc/bashrc: system-wide interactive bash config
      if [ -n "$PS1" ]; then
        shopt -s checkwinsize
        set +h

        if [ "$TERM" != "dumb" ] || [ -n "$INSIDE_EMACS" ]; then
          PROMPT_COLOR="1;31m"
          ((UID)) && PROMPT_COLOR="1;32m"
          if [ -n "$INSIDE_EMACS" ]; then
            PS1="\n\[\033[$PROMPT_COLOR\][\u@\h:\w]\\$\[\033[0m\] "
          else
            PS1="\n\[\033[$PROMPT_COLOR\][\[\e]0;\u@\h: \w\a\]\u@\h:\w]\\$\[\033[0m\] "
          fi
          if test "$TERM" = "xterm"; then
            PS1="\[\033]2;\h:\u:\w\007\]$PS1"
          fi
        fi

        eval "$(${pkgs.coreutils}/bin/dircolors -b)"
        alias ls='ls --color=auto'
      fi
    '';
  };
}
