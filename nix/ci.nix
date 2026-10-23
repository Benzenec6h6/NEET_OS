{
  pkgs,
  lib,
  neetModules, # NEET_OS の modules を受け取る
}: let
  # CI テスト用の最小ダミー評価
  testSystem = lib.evalModules {
    specialArgs = {inherit pkgs lib;};
    modules = [
      neetModules
      {
        # CI 評価を通すための最低限の必須定義だけ埋める
        boot.fileSystems."/".fsType = "btrfs";
        boot.fileSystems."/".device = "/dev/dummy";
        boot.loader.limine.enable = true;
        testing.vm.enable = true;

        # testing.vm が disks.devices を要求するので最小のものを置く
        disks.devices.main.partitions = [
          {
            name = "esp";
            size = "512M";
            content = {
              type = "vfat";
              mountPoint = "/boot";
            };
          }
          {
            name = "root";
            content = {
              type = "btrfs";
              mountPoint = "/";
            };
          }
        ];
      }
    ];
  };

  # etc 衝突チェック
  findConflicts = optionSet:
    lib.filterAttrs (_name: opt: (builtins.length (opt.definitionsWithLocations or [])) > 1) optionSet;

  etcConflicts = findConflicts testSystem.options.environment.etc;

  optionConflictsCheck =
    pkgs.runCommand "check-option-conflicts" {
      conflictsJson = builtins.toJSON (builtins.attrNames etcConflicts);
    } ''
      echo "$conflictsJson" > $out
      if [ "$conflictsJson" != "[]" ]; then
        echo "以下の environment.etc キーが複数箇所で定義されています:"
        echo "$conflictsJson"
        exit 1
      fi
    '';

  assertionsCheck =
    pkgs.runCommand "check-assertions" {
      failedJson = builtins.toJSON (
        map (a: a.message) (lib.filter (a: !a.assertion) (testSystem.config.assertions or []))
      );
    } ''
      echo "$failedJson" > $out
      if [ "$failedJson" != "[]" ]; then
        echo "assertion に失敗しています:"
        echo "$failedJson"
        exit 1
      fi
    '';

  evalCheck = pkgs.runCommand "check-eval" {} ''
    echo "${testSystem.config.system.build.toplevel}" > $out
  '';

  # mdev.conf 構文チェック
  mdevdConfCheck = let
    # 各モジュールから合成された services.mdevd.rules をファイル化
    mdevConfFile = pkgs.writeText "mdev.conf" testSystem.config.services.mdevd.rules;
  in
    pkgs.runCommand "check-mdevd-conf" {
      nativeBuildInputs = [pkgs.pkgsStatic.mdevd];
    } ''
      echo "Validating mdev.conf syntax with mdevd -N..."
      # 構文エラーがあれば非 0 で終了し、Nix のビルドログに line/column が出力される
      mdevd -N -f ${mdevConfFile}
      touch $out
    '';

  optionsDoc = pkgs.nixosOptionsDoc {options = testSystem.options;};
in {
  checks = {
    "option-conflicts" = optionConflictsCheck;
    "assertions" = assertionsCheck;
    "eval" = evalCheck;
    "mdevd-conf" = mdevdConfCheck;
  };
  docs = {
    optionsDoc = optionsDoc.optionsJSON;
  };
}
