{
  pkgs,
  lib,
  neetModules,
}: let
  testSystem = import ./ci/eval.nix {inherit pkgs lib neetModules;};

  osChecks = import ./ci/os.nix {inherit pkgs lib testSystem;};

  # 全チェック項目のリスト
  allChecks = builtins.attrValues osChecks;

  # サマリーレポート
  summaryReport = import ./ci/report.nix {
    inherit pkgs lib;
    checkList = allChecks;
  };

  optionsDoc = pkgs.nixosOptionsDoc {options = testSystem.options;};
in {
  checks =
    (builtins.mapAttrs (_name: v: v.path) osChecks)
    // {
      "report" = summaryReport;
    };

  docs = {
    optionsDoc = optionsDoc.optionsJSON;
  };
}
