{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.services.syslog;
in {
  options.services.syslog = {
    enable = mkOption {
      type = types.bool;
      default = true;
      description = "s6-socklog による syslog 受信 + s6-log による保存";
    };
    user = mkOption {
      type = types.str;
      default = "syslog";
      description = "s6-socklog が権限を落とす先のユーザー";
    };
    lameDuckTimeout = mkOption {
      type = types.int;
      default = 3000;
      description = "SIGTERM 後の flush 猶予 (ms)。0 は無期限待ちで、停止が終わらなくなる恐れがある。";
    };
  };

  config = mkIf cfg.enable {
    # gid が共有 gids に無いので、users.nix が同名の個人グループを自動生成する
    # uid/gid は既存ユーザーと衝突しない値に変えてよい
    neet.users.${cfg.user} = {
      uid = mkDefault 981;
      gid = mkDefault 981;
      description = "syslog receiver (s6-socklog)";
      home = "/var/empty";
      shell = "${pkgs.coreutils}/bin/false";
      createHome = false;
      createRuntimeDir = false;
    };

    system.s6-rc.services.syslog = {
      type = "longrun";
      notification-fd = 3;
      # umask 000: /dev/log を全ユーザーが書き込めるようにする
      # s6-socklog は bind してから権限を落とすので root で起動する
      run = ''
        #!${pkgs.runtimeShell}
        umask 000
        exec ${pkgs.s6}/bin/s6-envuidgid ${cfg.user} \
          ${pkgs.s6}/bin/s6-socklog -d3 -U -t ${toString cfg.lameDuckTimeout}
      '';

      log = {
        enable = true;
        dirs = ["/var/log/auth" "/var/log/messages"];
        # n / s / T と選択行は、直後の logdir 1つにだけ効く。logdir ごとに書くこと
        #   auth / authpriv → /var/log/auth
        #   それ以外すべて → /var/log/messages
        args = [
          "n10"
          "s1000000"
          "-"
          "+^(auth|authpriv)\\."
          "/var/log/auth"
          "n10"
          "s1000000"
          "-"
          "+."
          "-^(auth|authpriv)\\."
          "/var/log/messages"
        ];
      };
    };
  };
}
