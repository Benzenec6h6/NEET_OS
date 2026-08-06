{
  description = "NEET OS - A minimal s6/Rust based OS";

  outputs = {self}: let
    # 1. 外部リソースの取得
    sources = import ./npins;
    pkgs = import sources.nixpkgs {system = "x86_64-linux";};
    lib = pkgs.lib;

    # 2. 外部コンポーネント（Rustツール）のビルド
    etcSyncer = import ./etc-syncer/derivation.nix {inherit pkgs lib;};

    # 3. OSの「設計図」を評価 (NixOS風のモジュールシステム)
    # ここで /etc やインストールするパッケージを宣言的に定義します
    myOS = lib.evalModules {
      # configuration.nix で etcSyncer を使えるように渡す
      specialArgs = {inherit pkgs lib etcSyncer;};
      modules = [./configuration.nix];
    };

    # 5. 初期化スクリプト (init) の作成
    myInit = pkgs.writeScript "init" ''
      #!${pkgs.pkgsStatic.execline}/bin/execlineb -P
      export PATH /bin
      # 1. 複雑な初期化を呼び出す
      foreground { ${myOS.config.system.activationScript} }

      # 2. s6-svscan を実行 (exec なので PID 1 を引き継ぐ)
      s6-svscan /run/service
    '';

    # 6. VM用の RAMディスク (initrd) を組み立てる
    myInitrd = pkgs.makeInitrd {
      contents = [
        {
          object = myInit;
          symlink = "/init";
        }

        {
          object = "${myOS.config.system.path}/bin";
          symlink = "/bin";
        }
      ];
    };

    # 7. QEMU実行スクリプト (Runner)
    runner = import ./nix/runner.nix {
      inherit pkgs;
      kernel = pkgs.linux;
      initrd = myInitrd;
    };
  in {
    # 最終的な出力: nix run . で QEMU が走る
    apps.x86_64-linux.default = {
      type = "app";
      program = "${runner}/bin/run-vm";
    };
  };
}
