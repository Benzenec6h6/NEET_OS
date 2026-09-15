{
  config,
  lib,
  pkgs,
  ...
}: let
  kernel = config.boot.kernelPackages.kernel;
in {
  imports = [
    ./kernel.nix
    ./initrd.nix
    # 将来ここに limine.nix や efi.nix を追加します
  ];

  options = {
    boot.consoles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = ["tty1"];
      description = "カーネルおよびコンソール出力先候補（先頭が優先）";
    };
  };

  config = {
    system.build.kernel = kernel;
  };
}
