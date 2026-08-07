{
  description = "NEET OS - A minimal s6/Rust based OS";

  outputs = {self}: let
    sources = import ./npins;
    pkgs = import sources.nixpkgs {system = "x86_64-linux";};
    lib = pkgs.lib;

    # OSの評価
    myOS = lib.evalModules {
      specialArgs = {inherit pkgs lib;};
      modules = [./configuration.nix];
    };

    # Runner の作成
    # 評価結果の config.system.build.initrd を渡すだけ
    runner = import ./nix/runner.nix {
      inherit pkgs;
      kernel = pkgs.linux;
      initrd = myOS.config.system.build.initrd;
    };
  in {
    apps.x86_64-linux.default = {
      type = "app";
      program = "${runner}/bin/run-vm";
    };
  };
}
