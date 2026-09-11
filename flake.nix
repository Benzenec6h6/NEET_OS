{
  description = "NEET OS - A minimal s6/Rust based OS";

  outputs = {self}: let
    sources = import ./npins;
    pkgs = import sources.nixpkgs {system = "x86_64-linux";};
    lib = pkgs.lib;

    evalProfile = profilePath:
      lib.evalModules {
        specialArgs = {inherit pkgs lib;};
        modules = [profilePath];
      };

    myOS-VM = evalProfile ./profiles/vm-qemu;
    myOS-Desktop = evalProfile ./profiles/desktop;

    ci = import ./nix/ci.nix {
      inherit pkgs lib;
      profiles = {
        vm = myOS-VM;
        desktop = myOS-Desktop;
      };
    };
  in {
    debugConfig = {
      vm = myOS-VM.config;
      desktop = myOS-Desktop.config;
    };

    apps.x86_64-linux.default = {
      type = "app";
      program = "${myOS-VM.config.system.build.vm}/bin/run-vm";
    };

    packages.x86_64-linux = {
      default = myOS-VM.config.system.build.diskImage;
      vmImage = myOS-VM.config.system.build.diskImage;
      toplevelVm = myOS-VM.config.system.build.toplevel;
      toplevelDesktop = myOS-Desktop.config.system.build.toplevel;
      optionsDocVm = ci.docs.optionsDocVm;
      optionsDocDesktop = ci.docs.optionsDocDesktop;
    };

    checks.x86_64-linux = ci.checks;
  };
}
