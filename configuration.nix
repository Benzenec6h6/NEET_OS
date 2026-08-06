{
  pkgs,
  lib,
  etcSyncer,
  ...
}: {
  # 必要なモジュールをインポート
  imports = [
    ./modules/system/etc/default.nix
    ./modules/environment.nix
    ./modules/activation.nix
  ];

  # パッケージの設定 (execlineは modules/environment.nix で自動追加されるため除去)
  environment.systemPackages = [
    pkgs.pkgsStatic.busybox
    pkgs.pkgsStatic.s6
    etcSyncer
  ];

  # サービスの設定
  environment.etc = {
    "hostname".text = "neet-os\n";

    # 将来の書き込み可能性を考慮し、コピー対象にするため mode を明示
    "passwd" = {
      text = "root:x:0:0:root:/root:/bin/sh\n";
      mode = "0444";
    };

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
  };
}
