{
  pkgs,
  lib,
  ...
}: {
  imports = [
    ./modules/security
    ./modules/system/s6-rc
    ./modules/system/etc/default.nix
    ./modules/system/boot.nix
    ./modules/system/mdevd.nix
    ./modules/system/seatd.nix
    ./modules/system/users.nix
    ./modules/virtualisation/virtio.nix
    ./modules/filesystems
    ./modules/dbus.nix
    ./modules/networking
    ./modules/environment.nix
    ./modules/activation.nix
  ];

  environment.systemPackages = [
    pkgs.pkgsStatic.busybox
    pkgs.pkgsStatic.s6
    pkgs.pkgsStatic.s6-rc
    pkgs.sway
    pkgs.foot
    pkgs.mesa
    pkgs.libGL
    pkgs.fontconfig
    pkgs.dejavu_fonts
  ];

  environment.etc = {
    "hostname".text = "neet-os\n";
    "fonts/fonts.conf".source = "${pkgs.fontconfig.out}/etc/fonts/fonts.conf";
  };

  # s6-rc サービスとしてシステム初期化・実験用サービスを定義
  system.s6-rc.services = {
    meow = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        /bin/sh -c "while :; do echo NEET OS: meow!; sleep 10; done"
      '';
    };

    shell = {
      type = "longrun";
      run = ''
        #!/bin/execlineb -P
        getty -n -l /bin/sh 115200 ttyS0
      '';
    };
  };

  # サービス有効化
  services.mdevd.enable = true;
  services.seatd = {
    enable = true;
    group = "seat";
    debug = true;
  };

  services.dbus.enable = true;

  networking = {
    upInterfaces = ["lo" "eth0"];
    dhcpInterfaces = ["eth0"];
  };

  neet.security.enable = true;

  # sudo-rs の具体的なルール設定
  neet.security.privileges = {
    backend = "sudo-rs";
    rules = [
      {
        groups = ["wheel"];
        command = "ALL";
        requirePassword = true;
      }
    ];
  };

  neet.users = {
    root = {
      uid = 0;
      gid = 0;
      shell = "/bin/sh";
      home = "/root";
      description = "System Administrator";
      initialHashedPassword = "$y$j9T$lwc.8Oc5W7OwTWLCfDmfw/$IA4QRTrN.yPQcPwIiF8UULTrTDA3nZTM0p1JmQj/Jw4";
    };
    neet = {
      uid = 1000;
      gid = 1000;
      shell = "/bin/sh";
      description = "Primary User";
      extraGroups = ["video" "input" "seat" "wheel"];
      initialHashedPassword = "$y$j9T$lwc.8Oc5W7OwTWLCfDmfw/$IA4QRTrN.yPQcPwIiF8UULTrTDA3nZTM0p1JmQj/Jw4";
    };
  };

  boot.stage1.fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
  };

  boot.stage1.fileSystems."/nix/store" = {
    device = "/dev/vda";
    fsType = "ext4";
  };

  boot.stage2.fileSystems."/" = {
    device = "tmpfs";
    fsType = "tmpfs";
    alreadyMounted = true;
  };

  virtualisation.virtio.enable = true;
}
