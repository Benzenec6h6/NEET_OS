{
  pkgs,
  lib,
  ...
}: {
  # 必要なモジュールをインポート
  imports = [
    ./modules/system/etc/default.nix
    ./modules/system/boot.nix
    ./modules/system/mdevd.nix
    ./modules/system/seatd.nix
    ./modules/system/users.nix
    ./modules/filesystems
    ./modules/dbus.nix
    ./modules/networking
    ./modules/environment.nix
    ./modules/activation.nix
  ];

  # パッケージの設定 (execlineは modules/environment.nix で自動追加されるため除去)
  environment.systemPackages = [
    pkgs.pkgsStatic.busybox
    pkgs.pkgsStatic.s6
    pkgs.sway
    pkgs.foot
    pkgs.dbus
    pkgs.mesa
    pkgs.libGL
    pkgs.fontconfig
    pkgs.dejavu_fonts
  ];

  # サービスの設定
  environment.etc = {
    "hostname".text = "neet-os\n";

    # ログ付き meow サービス
    "s6-scan/meow/run" = {
      text = "#!/bin/execlineb -P\n/bin/sh -c \"while :; do echo NEET OS: meow!; sleep 10; done\"";
      mode = "0555";
    };
    "s6-scan/meow/log/run" = {
      text = "#!/bin/execlineb -P\nforeground { mkdir -p /var/log/meow }\ns6-log n3 s1000000 /var/log/meow";
      mode = "0555";
    };

    # getty シェル
    "s6-scan/shell/run" = {
      text = "#!/bin/execlineb -P\ngetty -n -l /bin/sh 115200 ttyS0";
      mode = "0555";
    };

    "fonts/fonts.conf".source = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
  };

  services.mdevd.enable = true;
  services.seatd = {
    enable = true;
    group = "seat"; # または "video" (users.nixで定義したグループ名に合わせる)
    debug = true; # 最初はログを詳しく見るために true にしておくと便利です
  };

  services.dbus.enable = true;

  neet.users = {
    root = {
      uid = 0;
      gid = 0;
      shell = "/bin/sh";
      home = "/root";
      description = "System Administrator";
    };
    neet = {
      uid = 1000;
      gid = 1000;
      shell = "/bin/sh";
      description = "Primary User";
      extraGroups = ["video" "input" "seat"];
    };
  };

  networking.upInterfaces = ["lo" "eth0"];

  fileSystems = {
    "/" = {
      device = "tmpfs"; # ルートは tmpfs
      fsType = "tmpfs";
      options = ["mode=0755"];
    };
    "/nix/store" = {
      device = "nixstore"; # 9pタグ
      fsType = "9p";
      options = ["trans=virtio" "version=9p2000.L" "msize=1048576" "readonly"];
      neededForBoot = true; # Stage 1 でマウントさせる！
    };
  };
}
