{
  config,
  pkgs,
  lib,
  ...
}: let
  cfg = config.services.gardendevd;

  package = pkgs.gardendevd.overrideAttrs (old: {
    version = "0.2-unstable-2026-07-03";

    src = old.src.override {
      tag = null;
      rev = "ec73dc569382404bc6620c9857b7e09206bc282e";
      hash = "sha256-8VOJFz5QtlyLbAf87rtNXSvnrfPoyQVAKwuD+YkfzdQ=";
    };

    mesonFlags = [
      (lib.mesonEnable "dracut" false)
      (lib.mesonEnable "uaccess" true)
    ];
  });
in {
  options.services.udev = {
    packages = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = [];
      description = "udev rules や hwdb を含むパッケージ群";
    };

    extraRules = lib.mkOption {
      type = lib.types.lines;
      default = "";
      description = "追加の udev rules";
    };
  };

  options.services.gardendevd = {
    package = lib.mkOption {
      type = lib.types.package;
      default = package;
      description = "gardendevd パッケージ";
    };

    debug = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "デバッグログの有効化";
    };

    extraArgs = lib.mkOption {
      type = with lib.types; listOf str;
      default = [];
    };

    path = lib.mkOption {
      type = with lib.types; listOf path;
      default = [];
    };
  };

  config = lib.mkIf (config.services.deviceManager == "gardendevd") {
    environment.systemPackages = [cfg.package];

    services.gardendevd.extraArgs = [
      "-K"
      "-v"
      (
        if cfg.debug
        then "debug"
        else "info"
      )
    ];

    services.gardendevd.path = [
      config.programs.coreutils.package
      pkgs.gnugrep
      pkgs.gnused
      pkgs.kmod
      pkgs.util-linux
    ];

    # gardendevd 付属ルール
    services.udev.packages = [cfg.package];

    # hwdb.bin の生成
    environment.etc."udev/hwdb.bin".source =
      pkgs.runCommand "gardendevd-hwdb.bin"
      {
        __structuredAttrs = true;
        preferLocalBuild = true;
        allowSubstitutes = false;
        packages = lib.unique config.services.udev.packages;
      }
      ''
        shopt -s nullglob
        mkdir -p root/etc/udev/hwdb.d
        for i in "''${packages[@]}"; do
          for j in "$i"/{etc,lib,var/lib}/udev/hwdb.d/*; do
            ln -s "$j" "root/etc/udev/hwdb.d/$(basename "$j")"
          done
        done

        ${cfg.package}/bin/gardendev-hwdb update --root "$PWD/root"
        mv root/etc/udev/hwdb.bin "$out"
      '';

    # rules.d の生成
    environment.etc."udev/rules.d".source = let
      extraRulesPkg = pkgs.writeTextFile {
        name = "99-local-extra.rules";
        destination = "/lib/udev/rules.d/99-local-extra.rules";
        text = config.services.udev.extraRules;
      };
      allPackages = lib.unique (config.services.udev.packages ++ lib.optional (config.services.udev.extraRules != "") extraRulesPkg);
    in
      pkgs.runCommand "gardendevd-rules"
      {
        __structuredAttrs = true;
        preferLocalBuild = true;
        allowSubstitutes = false;
        packages = allPackages;
      }
      ''
        mkdir -p "$out"
        shopt -s nullglob

        for i in "''${packages[@]}"; do
          for j in "$i"/{etc,lib,var/lib}/udev/rules.d/*; do
            cat "$j" > "$out/$(basename "$j")"
          done
        done

        # gardendevd 自身のルールを最優先
        for j in ${cfg.package}/lib/udev/rules.d/*; do
          cat "$j" > "$out/$(basename "$j")"
        done

        for i in "$out"/*.rules; do
          substituteInPlace "$i" \
            --replace-quiet \"/sbin/modprobe \"${lib.getExe' pkgs.kmod "modprobe"} \
            --replace-quiet \"/sbin/mdadm \"${pkgs.mdadm}/sbin/mdadm \
            --replace-quiet \"/sbin/blkid \"${pkgs.util-linux}/sbin/blkid \
            --replace-quiet \"/bin/mount \"${pkgs.util-linux}/bin/mount \
            --replace-quiet /usr/bin/readlink ${lib.getExe' config.programs.coreutils.package "readlink"} \
            --replace-quiet /usr/bin/cat ${lib.getExe' config.programs.coreutils.package "cat"} \
            --replace-quiet /usr/bin/basename ${lib.getExe' config.programs.coreutils.package "basename"} 2>/dev/null
        done
      '';

    system.activation.scripts.gardendevd = lib.mkIf config.boot.kernel.enable {
      text = ''
        if [ -e /proc/sys/kernel/hotplug ]; then
          echo "" > /proc/sys/kernel/hotplug
        fi
        if [ -e /sys/module/firmware_class/parameters/path ]; then
          echo -n "${config.hardware.firmware}/lib/firmware" > /sys/module/firmware_class/parameters/path
        fi
      '';
    };

    system.s6-rc.services = {
      # 1. デーモン本体 (共通名 devd)
      devd = {
        type = "longrun";
        run = ''
          #!/bin/sh
          export PATH="${lib.makeBinPath cfg.path}:$PATH"
          exec ${cfg.package}/bin/gardendevd ${lib.escapeShellArgs cfg.extraArgs}
        '';
      };

      # 2. コールドプラグ (共通名 devd-coldplug)
      devd-coldplug = {
        type = "oneshot";
        dependencies = ["devd"];
        up = ''
          #!/bin/sh
          ${cfg.package}/bin/gardendevctl trigger -c add -t all
          ${cfg.package}/bin/gardendevctl settle -t 30
        '';
      };
    };
  };
}
