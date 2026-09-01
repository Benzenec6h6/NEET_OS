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

    image = import ./nix/image.nix {
      inherit pkgs lib;
      config = myOS.config;
      stage2Init = myOS.config.system.build.toplevel.stage2Init;
    };

    # 評価結果の config.system.build.initrd を渡すだけ
    runner = import ./nix/runner.nix {
      inherit pkgs;
      inherit image;
      kernel = myOS.config.system.build.kernel;
      initrd = myOS.config.system.build.initrd;
    };
  in {
    debugConfig = myOS.config;

    apps.x86_64-linux.default = {
      type = "app";
      program = "${runner}/bin/run-vm";
    };
  };
}
