{
  description = "NEET OS - A minimal s6/Rust based OS";

  outputs = {self}: let
    sources = import ./npins;
    pkgs = import sources.nixpkgs {system = "x86_64-linux";};
    lib = pkgs.lib;

    ci = import ./nix/ci.nix {
      inherit pkgs lib;
      neetModules = ./modules;
    };
  in {
    # 外部(NEET_dots)に提供するモジュール群
    nixosModules.default = ./modules;

    # 外部から簡単に設定をビルドできるようにするヘルパー関数
    lib.evalSystem = userModules:
      lib.evalModules {
        specialArgs = {inherit pkgs lib;};
        modules = [./modules] ++ userModules;
      };

    # CI チェック
    checks.x86_64-linux = ci.checks;

    # オプション仕様書 (ドキュメント)
    packages.x86_64-linux.optionsDoc = ci.docs.optionsDoc;
  };
}
