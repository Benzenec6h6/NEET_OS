{
  config,
  pkgs,
  lib,
  ...
}: let
  caBundle = "${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt";
in {
  options.security.pki = {
    caBundle = lib.mkOption {
      type = lib.types.path;
      default = caBundle;
      readOnly = true;
      description = "Path to the default CA certificate bundle.";
    };
  };

  config = {
    # 互換性のため各標準パスに配置
    environment.etc."ssl/certs/ca-certificates.crt".source = caBundle;
    environment.etc."ssl/certs/ca-bundle.crt".source = caBundle;

    # システム全体に cacert パッケージを導入
    environment.systemPackages = [pkgs.cacert];
  };
}
