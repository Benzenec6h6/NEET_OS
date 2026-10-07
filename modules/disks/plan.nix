{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.disks;
  imp = config.impermanence;
  inherit (builtins) substring hashString attrNames elem;

  # ---- 識別子は eval 時に確定させる（UUID が eval 時に分からない問題の回避） ----
  hash = seed: hashString "sha256" seed;
  mkUuid = seed: let
    h = hash seed;
  in "${substring 0 8 h}-${substring 8 4 h}-4${substring 12 3 h}-8${substring 15 3 h}-${substring 18 12 h}";
  mkVolumeId = seed: let
    h = lib.toUpper (substring 0 8 (hash seed));
  in "${substring 0 4 h}-${substring 4 4 h}";

  labelMax = {
    vfat = 11;
    ext4 = 16;
    btrfs = 255;
    swap = 15;
  };
  defaultTypeCode = {
    vfat = "ef00";
    ext4 = "8300";
    btrfs = "8300";
    swap = "8200";
  };

  alwaysNeeded = ["/" "/nix" "/nix/store" "/usr"] ++ lib.optional imp.enable imp.persistPath;
  neededFor = mp: explicit: reset:
    if explicit != null
    then explicit
    else reset || elem mp alwaysNeeded;

  # ---- 宣言 → 確定済みの値 ----
  resolveContent = seed: part: c: {
    inherit (c) type;
    label =
      if c.label != null
      then c.label
      else
        lib.substring 0 labelMax.${c.type} (
          if c.type == "vfat"
          then lib.toUpper part.name
          else part.name
        );
    uuid =
      if c.uuid != null
      then c.uuid
      else if c.type == "vfat"
      then mkVolumeId seed
      else mkUuid seed;
    inherit (c) mountPoint;
    mountOptions = c.options;
    mkfsArgs = c.extraMkfsArgs;
    subvolumes = map (name: {
      inherit name;
      inherit (c.subvolumes.${name}) mountPoint options;
    }) (attrNames c.subvolumes);
  };

  resolvePartition = diskName: p: let
    seed = "${diskName}/${p.name}";
  in {
    inherit (p) name size;
    typeCode =
      if p.typeCode != null
      then p.typeCode
      else if p.content != null
      then defaultTypeCode.${p.content.type}
      else "8300";
    guid =
      if p.guid != null
      then p.guid
      else mkUuid "${seed}/partition";
    content =
      if p.content == null
      then null
      else resolveContent seed p p.content;
  };

  diskNames = attrNames cfg.devices;

  resolvedDisks =
    map (name: {
      inherit name;
      inherit (cfg.devices.${name}) device;
      partitions = map (resolvePartition name) cfg.devices.${name}.partitions;
    })
    diskNames;

  # ---- 宣言 → boot.fileSystems ----
  deviceFor = rp:
    if cfg.deviceReference == "partuuid"
    then "PARTUUID=${rp.guid}"
    else "UUID=${rp.content.uuid}";

  fsEntriesFor = p: rp: let
    c = p.content;
    device = deviceFor rp;
  in
    if c == null || c.type == "swap"
    then []
    else if c.type == "btrfs" && c.subvolumes != {}
    then
      lib.concatMap (name: let
        sv = c.subvolumes.${name};
      in
        lib.optional (sv.mountPoint != null) {
          name = sv.mountPoint;
          value = {
            inherit device;
            fsType = "btrfs";
            options = ["subvol=${name}"] ++ sv.options;
            neededForBoot = neededFor sv.mountPoint sv.neededForBoot sv.resetOnBoot;
            inherit (sv) resetOnBoot keepOldRoots;
          };
        }) (attrNames c.subvolumes)
    else
      lib.optional (c.mountPoint != null) {
        name = c.mountPoint;
        value = {
          inherit device;
          fsType = c.type;
          inherit (c) options;
          neededForBoot = neededFor c.mountPoint c.neededForBoot false;
        };
      };

  allEntries =
    lib.concatMap (
      dname:
        lib.concatMap (p: fsEntriesFor p (resolvePartition dname p)) cfg.devices.${dname}.partitions
    )
    diskNames;

  allMountPoints = map (e: e.name) allEntries;

  # ---- assertions 用 ----
  allPartitions = lib.concatMap (dname: map (p: {inherit dname p;}) cfg.devices.${dname}.partitions) diskNames;
  isBad = x: builtins.match "[0-9]+[KMGT]|100%" x.p.size == null;
  restNotLast = lib.concatMap (dname: let
    ps = cfg.devices.${dname}.partitions;
  in
    lib.filter (p: p.size == "100%") (lib.take ((lib.length ps) - 1) ps))
  diskNames;
  dupPartNames = lib.concatMap (dname: let
    names = map (p: p.name) cfg.devices.${dname}.partitions;
  in
    map (n: "${dname}/${n}") (lib.filter (n: lib.count (x: x == n) names > 1) (lib.unique names)))
  diskNames;
  withContent = lib.filter (x: x.p.content != null) allPartitions;
  badSubvolNames = lib.concatMap (x:
    lib.filter (n: n == "" || lib.hasInfix "/" n) (attrNames x.p.content.subvolumes))
  withContent;
  subvolOnNonBtrfs = lib.filter (x: x.p.content.type != "btrfs" && x.p.content.subvolumes != {}) withContent;
  mixedMount = lib.filter (x: x.p.content.type == "btrfs" && x.p.content.subvolumes != {} && x.p.content.mountPoint != null) withContent;
  swapMounted = lib.filter (x: x.p.content.type == "swap" && x.p.content.mountPoint != null) withContent;
  resetWithoutMount = lib.concatMap (x:
    lib.filter (n: let sv = x.p.content.subvolumes.${n}; in sv.resetOnBoot && sv.mountPoint == null) (attrNames x.p.content.subvolumes))
  withContent;
  unstableDevices = lib.filter (d: d != null && !(lib.hasPrefix "/dev/disk/by-" d)) (map (n: cfg.devices.${n}.device) diskNames);

  diskTools = with pkgs; [gptfdisk dosfstools mtools btrfs-progs e2fsprogs util-linux coreutils findutils];

  diskPlan = pkgs.writeText "disk-plan.json" (builtins.toJSON {
    version = 1;
    disks = resolvedDisks;
  });
in {
  config = lib.mkIf (cfg.devices != {}) {
    assertions = [
      {
        assertion = cfg.package != null;
        message = "disks: disks.package に disk-setup を含むパッケージを指定してください。";
      }
      {
        assertion = lib.filter isBad allPartitions == [];
        message = "disks: size は 512M / 4G / 100% の形式で指定してください: ${toString (map (x: "${x.dname}/${x.p.name}=${x.p.size}") (lib.filter isBad allPartitions))}";
      }
      {
        assertion = restNotLast == [];
        message = "disks: size = \"100%\" は各ディスクの最後のパーティションにのみ使えます。";
      }
      {
        assertion = dupPartNames == [];
        message = "disks: パーティション名が重複しています: ${toString dupPartNames}";
      }
      {
        assertion = lib.filter (m: !(lib.hasPrefix "/" m)) allMountPoints == [];
        message = "disks: mountPoint は絶対パスで指定してください。";
      }
      {
        assertion = lib.filter (m: lib.count (x: x == m) allMountPoints > 1) (lib.unique allMountPoints) == [];
        message = "disks: mountPoint が重複しています: ${toString (lib.filter (m: lib.count (x: x == m) allMountPoints > 1) (lib.unique allMountPoints))}";
      }
      {
        assertion = badSubvolNames == [];
        message = "disks: subvolume 名は空にできず、'/' も含められません: ${toString badSubvolNames}";
      }
      {
        assertion = subvolOnNonBtrfs == [];
        message = "disks: subvolumes は btrfs でのみ使えます。";
      }
      {
        assertion = mixedMount == [];
        message = "disks: btrfs で subvolumes を使う場合、content.mountPoint は null にして subvolume 側で指定してください。";
      }
      {
        assertion = swapMounted == [];
        message = "disks: swap に mountPoint は指定できません。";
      }
      {
        assertion = resetWithoutMount == [];
        message = "disks: resetOnBoot = true の subvolume には mountPoint が必要です: ${toString resetWithoutMount}";
      }
      {
        assertion = unstableDevices == [];
        message = "disks: device は /dev/disk/by-id などの安定した名前で指定してください（/dev/sdX は不可）。VM 等は device = null にして --device を使います: ${toString unstableDevices}";
      }
    ];

    # 手書きの boot.fileSystems で上書きできるよう、すべて mkDefault
    boot.fileSystems = lib.listToAttrs (map (e: {
        inherit (e) name;
        value = lib.mapAttrs (_: lib.mkDefault) e.value;
      })
      allEntries);

    system.build.diskPlan = diskPlan;

    # neet-disk format [--yes] [--force] [--disk NAME] [--device DEV]
    # neet-disk mount /mnt
    system.build.diskTool = pkgs.writeShellScriptBin "neet-disk" ''
      export PATH=${lib.makeBinPath diskTools}:$PATH
      cmd="''${1:?usage: neet-disk <format|mount> [args...]}"
      shift
      exec ${cfg.package}/bin/disk-setup "$cmd" ${diskPlan} "$@"
    '';
  };
}
