{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.users;

  userOpts = types.submodule {
    options = {
      uid = mkOption {
        type = types.int;
        description = "User ID";
      };
      gid = mkOption {
        type = types.int;
        description = "Group ID";
      };
      shell = mkOption {
        type = types.str;
        default = "/bin/sh";
        description = "Default shell";
      };
      home = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "Home directory";
      };
      createHome = mkOption {
        type = types.bool;
        default = true;
        description = "起動時にホームディレクトリを自動作成するかどうか";
      };
      createRuntimeDir = mkOption {
        type = types.bool;
        default = true;
        description = "起動時に /run/user/<uid> (XDG_RUNTIME_DIR) を自動作成するかどうか";
      };
      description = mkOption {
        type = types.str;
        default = "";
        description = "GECOS description";
      };
      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [];
        description = "The user's auxiliary groups.";
      };
      initialHashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
        description = "パスワードハッシュ";
      };
    };
  };

  # /etc/passwd と /etc/group の生成ロジック（既存のまま）
  mkPasswdLine = name: u: let
    homeDir =
      if u.home != null
      then u.home
      else "/home/${name}";
  in "${name}:x:${toString u.uid}:${toString u.gid}:${u.description}:${homeDir}:${u.shell}";

  sharedGids = attrValues config.neet.gids;
  userGroups = filterAttrs (_name: gid: !elem gid sharedGids) (mapAttrs (_name: u: u.gid) cfg);
  allGroups = config.neet.gids // userGroups;

  getUsersInGroup = groupName: gid: let
    matchingUsers =
      filterAttrs (
        username: userCfg:
          elem groupName userCfg.extraGroups
          || (hasAttr groupName config.neet.gids && userCfg.gid == gid)
      )
      cfg;
  in
    attrNames matchingUsers;

  mkGroupLine = groupName: gid: let
    members = getUsersInGroup groupName gid;
    memberStr = concatStringsSep "," members;
  in "${groupName}:x:${toString gid}:${memberStr}";

  # ★ ここでユーザー用のディレクトリを system.stateDirectories の形式に変換
  userDirectories = concatLists (mapAttrsToList (
      name: u: let
        homePath =
          if u.home != null
          then u.home
          else "/home/${name}";
      in
        # 1. ホームディレクトリ (/home/<user>)
        optional u.createHome {
          path = homePath;
          mode = "0755";
          user = name;
          group = toString u.gid;
        }
        # 2. ランタイムディレクトリ (/run/user/<uid>)
        # UID >= 1000 の通常ユーザーのみ
        ++ optional (u.createRuntimeDir && u.uid >= 1000) {
          path = "/run/user/${toString u.uid}";
          mode = "0700";
          user = name;
          group = toString u.gid;
        }
    )
    cfg);
in {
  options.neet = {
    users = mkOption {
      type = types.attrsOf userOpts;
      default = {};
      description = "User definitions for NEET_OS";
    };

    gids = mkOption {
      type = types.attrsOf types.int;
      default = {};
      description = "System Shared Group IDs";
    };
  };

  config = {
    neet.gids = {
      root = lib.mkDefault 0;
      tty = lib.mkDefault 5;
      wheel = lib.mkDefault 10;
      video = lib.mkDefault 44;
      input = lib.mkDefault 104;
      seat = lib.mkDefault 150;
      audio = lib.mkDefault 29;
    };

    environment.etc."passwd".text =
      concatStringsSep "\n" (mapAttrsToList mkPasswdLine cfg) + "\n";

    environment.etc."group".text =
      concatStringsSep "\n" (mapAttrsToList mkGroupLine allGroups) + "\n";

    # ★ ユーザー用のディレクトリを全体の stateDirectories に合流させる
    system.stateDirectories = userDirectories;
  };
}
