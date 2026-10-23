{
  pkgs,
  lib,
  neetModules,
}: let
  testSystem = import ./ci/eval.nix {inherit pkgs lib neetModules;};

  osChecks = import ./ci/os.nix {inherit pkgs lib testSystem;};
  rustChecks = import ./ci/rust.nix {
    inherit pkgs;
    rustSourcePath = ../pkgs/inieet;
  };

  # 全チェック項目のリスト
  allChecks = (builtins.attrValues osChecks) ++ (builtins.attrValues rustChecks);

  # サマリーレポート
  summaryReport = import ./ci/report.nix {
    inherit pkgs lib;
    checkList = allChecks;
  };

  optionsDoc = pkgs.nixosOptionsDoc {options = testSystem.options;};
in {
  checks =
    (builtins.mapAttrs (_name: v: v.path) osChecks)
    // (builtins.mapAttrs (_name: v: v.path) rustChecks)
    // {
      "report" = summaryReport;
    };

  docs = {
    optionsDoc = optionsDoc.optionsJSON;
  };
}
