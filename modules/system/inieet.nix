{
  pkgs,
  lib,
  ...
}: let
  inieet = pkgs.callPackage ../../pkgs/inieet {};
in {
  config = {
    # system.build に各 Rust バイナリをぶら下げる
    system.build.stage1Mount = inieet.neetMount;
    system.build.neetActivate = inieet.neetActivate;
    system.build.neetSecret = inieet.neetSecret;
    system.build.neetUki = inieet.neetUki;
    system.build.limineInstall = inieet.limineInstall;
    system.build.efistubSync = inieet.efistubSync;
    system.build.espSync = inieet.espSync;
    system.build.bootspecWrite = inieet.bootspecWrite;
    system.build.diskSetup = inieet.diskSetup;

    # システムの一般 PATH に neetActivate などを登録
    environment.systemPackages = [
      inieet.neetActivate
      inieet.espSync
      inieet.diskSetup
      inieet.neetSecret
    ];
  };
}
