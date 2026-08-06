{
  pkgs,
  lib,
  config,
  ...
}: {
  options = {
    # 各モジュール（etcなど）からスクリプト断片を登録できるようにする
    system.activationScripts = lib.mkOption {
      type = lib.types.attrsOf lib.types.lines;
      default = {};
    };

    system.activationScript = lib.mkOption {
      type = lib.types.package;
      internal = true;
    };
  };

  config.system.activationScript = pkgs.writeScript "activate" ''
    #!/bin/execlineb -P
    export PATH /bin

    # 必須のマウント処理
    if { mkdir -p /proc /sys /dev /etc /run /root /var/log }
    if { mount -t proc proc /proc }
    if { mount -t sysfs sysfs /sys }
    if { mount -t devtmpfs devtmpfs /dev }

    # 各モジュールで登録された activationScripts を順番に実行
    ${lib.concatStringsSep "\n" (
      map (name: "foreground { /bin/sh -c ${lib.escapeShellArg config.system.activationScripts.${name}} }")
      (lib.attrNames config.system.activationScripts)
    )}

    # s6サービスの準備 (将来的に s6 モジュールへ切り出し可能な部分)
    foreground { rm -rf /run/service }
    foreground { mkdir -p /run/service }
    foreground { /bin/sh -c "cp -rL /etc/s6-scan/* /run/service/" }
    foreground { /bin/sh -c "find /run/service -name run -exec chmod +x {} +" }
  '';
}
