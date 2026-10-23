{
  pkgs,
  lib,
  testSystem,
}: let
  findConflicts = optionSet:
    lib.filterAttrs (_name: opt: (builtins.length (opt.definitionsWithLocations or [])) > 1) optionSet;

  etcConflicts = findConflicts testSystem.options.environment.etc;

  optionConflictsCheck =
    pkgs.runCommand "check-option-conflicts" {
      conflictsJson = builtins.toJSON (builtins.attrNames etcConflicts);
    } ''
      mkdir -p $out
      if [ "$conflictsJson" != "[]" ]; then
        echo "FAIL" > $out/status
        echo "以下の environment.etc キーが複数箇所で定義されています:" > $out/log.txt
        echo "$conflictsJson" >> $out/log.txt
      else
        echo "OK" > $out/status
        echo "No conflicts found." > $out/log.txt
      fi
    '';

  assertionsCheck =
    pkgs.runCommand "check-assertions" {
      failedList = lib.filter (a: !a.assertion) (testSystem.config.assertions or []);
    } ''
      mkdir -p $out
      failedJson='${builtins.toJSON (map (a: a.message) failedList)}'
      if [ "$failedJson" != "[]" ]; then
        echo "FAIL" > $out/status
        echo "assertion に失敗しています:" > $out/log.txt
        echo "$failedJson" >> $out/log.txt
      else
        echo "OK" > $out/status
        echo "All assertions passed." > $out/log.txt
      fi
    '';

  mdevdConfCheck = let
    mdevConfFile = pkgs.writeText "mdev.conf" testSystem.config.services.mdevd.rules;
  in
    pkgs.runCommand "check-mdevd-conf" {
      nativeBuildInputs = [pkgs.pkgsStatic.mdevd];
    } ''
      mkdir -p $out
      if mdevd -N -f ${mdevConfFile} > $out/log.txt 2>&1; then
        echo "OK" > $out/status
      else
        echo "FAIL" > $out/status
      fi
    '';
in {
  "option-conflicts" = {
    name = "Option Conflicts";
    path = optionConflictsCheck;
  };
  "assertions" = {
    name = "Assertions";
    path = assertionsCheck;
  };
  "mdevd-conf" = {
    name = "mdevd.conf Syntax";
    path = mdevdConfCheck;
  };
}
