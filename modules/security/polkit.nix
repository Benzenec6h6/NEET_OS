{
  pkgs,
  config,
  lib,
  ...
}: {
  config = lib.mkIf config.neet.security.enable {
    # D-Bus ポリシーとパッケージ
    services.dbus.packages = [pkgs.polkit.out];
    environment.systemPackages = [pkgs.polkit];

    # 1. Nixpkgs がハードコードしている "polkituser" を定義
    neet.gids.polkituser = lib.mkDefault 999;
    neet.users.polkituser = {
      uid = lib.mkDefault 999;
      gid = config.neet.gids.polkituser;
      description = "Polkit daemon user";
      shell = "/bin/sh";
      home = "/var/empty";
      createHome = false;
    };

    # 2. polkituser 所有でステートディレクトリを確保
    system.stateDirectories = [
      {
        path = "/var/lib/polkit-1";
        mode = "0700";
        user = "polkituser";
        group = "polkituser";
      }
    ];

    # 3. デフォルトルールの配置
    environment.etc."polkit-1/rules.d/50-default.rules".text = ''
      polkit.addAdminRule(function(action, subject) {
          return ["unix-group:wheel"];
      });
    '';

    # 4. s6-rc サービス定義
    system.s6-rc.services.polkitd = {
      type = "longrun";
      dependencies =
        ["dbus"]
        ++ lib.optional config.services.syslog.enable "syslog";
      run = ''
        #!/bin/execlineb -P
        ${pkgs.polkit.out}/lib/polkit-1/polkitd --no-debug
      '';
    };
  };
}
