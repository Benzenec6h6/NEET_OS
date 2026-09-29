{
  pkgs,
  lib,
  ...
}: let
  inieet = pkgs.callPackage ../../pkgs/inieet {};
in {
  config = {
    # system.build に各 Rust バイナリをぶら下げる
    system.build.earlyInit = inieet.earlyInit;
    system.build.systemInit = inieet.systemInit;
    system.build.limineInstall = inieet.limineInstall;
    system.build.efistubInstall = inieet.efistubInstall;
    system.build.bootspecWrite = inieet.bootspecWrite;

    # システムの一般 PATH に systemInit などを登録
    environment.systemPackages = [
      inieet.systemInit
    ];
  };
}
