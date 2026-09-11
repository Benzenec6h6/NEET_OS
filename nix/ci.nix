{
  pkgs,
  lib,
  profiles, # { vm = myOS-VM; desktop = myOS-Desktop; } の形で渡す
}: let
  # environment.etc 配下で同じキーが複数箇所から定義されていないかを検出
  findConflicts = optionSet:
    lib.filterAttrs
    (_name: opt: (builtins.length (opt.definitionsWithLocations or [])) > 1)
    optionSet;

  # 1プロファイル分のチェック一式を生成するヘルパー
  mkProfileChecks = name: myOS: let
    etcConflicts = findConflicts myOS.options.environment.etc;

    optionConflictsCheck =
      pkgs.runCommand "check-option-conflicts-${name}" {
        conflictsJson = builtins.toJSON (builtins.attrNames etcConflicts);
      } ''
        echo "$conflictsJson" > $out
        if [ "$conflictsJson" != "[]" ]; then
          echo "[${name}] 以下の environment.etc キーが複数箇所で定義されています:"
          echo "$conflictsJson"
          exit 1
        fi
      '';

    # assertions を評価してfailさせる(モジュール側でconfig.assertionsを使っている前提)
    assertionsCheck =
      pkgs.runCommand "check-assertions-${name}" {
        failedJson = builtins.toJSON (
          map (a: a.message) (lib.filter (a: !a.assertion) (myOS.config.assertions or []))
        );
      } ''
        echo "$failedJson" > $out
        if [ "$failedJson" != "[]" ]; then
          echo "[${name}] assertion に失敗しています:"
          echo "$failedJson"
          exit 1
        fi
      '';

    # toplevelまで評価が通ることの確認(desktopはswitch_root等が無くても評価自体は通るはず)
    evalCheck = pkgs.runCommand "check-eval-${name}" {} ''
      echo "${myOS.config.system.build.toplevel}" > $out
    '';
  in {
    "option-conflicts-${name}" = optionConflictsCheck;
    "assertions-${name}" = assertionsCheck;
    "eval-${name}" = evalCheck;
  };

  vmChecks = mkProfileChecks "vm" profiles.vm;
  desktopChecks = mkProfileChecks "desktop" profiles.desktop;

  optionsDocVm = pkgs.nixosOptionsDoc {options = profiles.vm.options;};
  optionsDocDesktop = pkgs.nixosOptionsDoc {options = profiles.desktop.options;};
in {
  checks = vmChecks // desktopChecks;
  docs = {
    optionsDocVm = optionsDocVm.optionsJSON;
    optionsDocDesktop = optionsDocDesktop.optionsJSON;
  };
}
