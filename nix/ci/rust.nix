{
  pkgs,
  rustSourcePath,
}: let
  rustDuplicatesCheck =
    pkgs.runCommand "check-rust-duplicates" {
      nativeBuildInputs = [pkgs.jscpd];
    } ''
      mkdir -p $out
      if jscpd ${rustSourcePath} --pattern "**/*.rs" --min-tokens 40 --threshold 0 > $out/log.txt 2>&1; then
        echo "OK" > $out/status
      else
        echo "FAIL" > $out/status
      fi
    '';

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
  "rust-duplicates" = {
    name = "Rust Duplications (jscpd)";
    path = rustDuplicatesCheck;
  };
  "rust-fmt" = {
    name = "Rust Formatting (rustfmt)";
    path = rustFmtCheck;
  };
}
