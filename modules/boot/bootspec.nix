{
  config,
  pkgs,
  lib,
  ...
}: let
  bootspecWrite = config.system.build.bootspecWrite;
  kernelParamsStr = lib.concatStringsSep " " config.boot.kernelParams;
in {
  # toplevel の runCommand の中から呼ばれるスクリプトスニペット
  system.build.generateBootspec = ''
    ${bootspecWrite}/bin/bootspec-write \
      --system ${pkgs.stdenv.hostPlatform.system} \
      --kernel $out/kernel \
      --initrd $out/initrd \
      --init $out/init \
      --kernel-params "${kernelParamsStr}" \
      --label "NEET_OS (Linux ${config.boot.kernelPackages.kernel.modDirVersion})" \
      --toplevel $out \
      --out $out/boot.json
  '';
}
