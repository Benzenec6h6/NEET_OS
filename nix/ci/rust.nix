{
  pkgs,
  rustSourcePath,
}: let
  rustFmtCheck =
    pkgs.runCommand "check-rust-fmt" {
      nativeBuildInputs = [pkgs.rustfmt];
    } ''
      mkdir -p $out
      if find ${rustSourcePath} -name "*.rs" -exec rustfmt --check {} + > $out/log.txt 2>&1; then
        echo "OK" > $out/status
      else
        echo "FAIL" > $out/status
      fi
    '';
in {
  "rust-fmt" = {
    name = "Rust Formatting (rustfmt)";
    path = rustFmtCheck;
  };
}
