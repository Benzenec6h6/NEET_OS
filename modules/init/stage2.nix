{
  config,
  pkgs,
  ...
}: let
  headBin = "${pkgs.coreutils}/bin/head";

  stage2Init = pkgs.replaceVarsWith {
    src = ./stage2.execline;
    replacements = {
      execline = "${config.environment.execline}";
      s6 = "${pkgs.s6}";
      s6Rc = "${pkgs.s6-rc}";
      head = headBin;
      core = "${config.system.build.core}";
      neetActivateBin = "${config.system.etc.bin}/bin/neet-activate";
    };
    isExecutable = true;
  };
in {
  config = {
    # 1. stage2Init の提供
    system.build.stage2Init = stage2Init;

    # ★ 2. Stage 2 (s6) に必要なディレクトリをここで自己完結して宣言
    system.stateDirectories = [
      {
        path = "/run/service";
        mode = "0755";
      }
    ];
  };
}
