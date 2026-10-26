{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.boot.secureBoot;
in {
  options.boot.secureBoot = {
    enable = lib.mkEnableOption "Secure Boot signing and enforcement for NEET OS";

    keyPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl/keys/db/db.key";
      description = "セキュアブート秘密鍵 (db.key) のパス";
    };

    certPath = lib.mkOption {
      type = lib.types.str;
      default = "/var/lib/sbctl/keys/db/db.pem";
      description = "セキュアブート証明書 (db.pem) のパス";
    };
  };

  config = lib.mkIf cfg.enable {
    # セキュアブートが有効なら、自動的に UKI を有効化する
    boot.uki.enable = lib.mkDefault true;

    # 万が一、ユーザーが明示的に uki.enable = false にしていたらエラーで弾く
    assertions = [
      {
        assertion = config.boot.uki.enable;
        message = "Secure Boot requires UKI (boot.uki.enable = true) to protect initrd and cmdline from tampering.";
      }
    ];

    # 署名ツールと鍵管理ツールをシステムに導入
    environment.systemPackages = [
      pkgs.sbctl
      pkgs.sbsigntool
    ];

    system.stateDirectories = [
      {
        path = "/var/lib/sbctl/keys";
        mode = "0700";
        user = "root";
        group = "root";
      }
    ];
  };
}
