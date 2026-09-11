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
        description = "パスワードハッシュ (例: mkpasswd -m sha-512 で生成した文字列)";
      };
    };
  };

  # 1. /etc/passwd の生成
  mkPasswdLine = name: u: let
    homeDir =
      if u.home != null
      then u.home
      else "/home/${name}";
  in "${name}:x:${toString u.uid}:${toString u.gid}:${u.description}:${homeDir}:${u.shell}";

  # 2. ユーザー個人の主グループを動的抽出
  userGroups = mapAttrs (_name: u: u.gid) cfg;

  # 3. システム定義の共有グループとユーザー個人のグループを安全に合体
  allGroups = let
    # 重複しているグループ名を取得
    overlapGroupNames = attrNames (intersectAttrs config.neet.gids userGroups);

    # GIDが一致していない不整合なグループを検出
    mismatched = filter (name: config.neet.gids.${name} != userGroups.${name}) overlapGroupNames;
  in
    if mismatched != []
    then throw "GID不一致エラー: グループ [ ${concatStringsSep ", " mismatched} ] の GID が neet.gids と neet.users 間で一致していません。"
    else config.neet.gids // userGroups;

  # 4. 各グループの所属メンバーを取得
  getUsersInGroup = groupName: let
    matchingUsers = filterAttrs (username: userCfg: elem groupName userCfg.extraGroups) cfg;
  in
    attrNames matchingUsers;

  # 5. /etc/group の1行をフォーマット生成
  mkGroupLine = groupName: gid: let
    members = getUsersInGroup groupName;
    memberStr = concatStringsSep "," members;
  in "${groupName}:x:${toString gid}:${memberStr}";

  # 6. Rust 側に渡すユーザー制御用の JSON 設定ファイルを出力
  userControlJson =
    mapAttrsToList (name: u: {
      username = name;
      uid = u.uid;
      createHome = u.createHome;
      createRuntimeDir = u.createRuntimeDir;
    })
    cfg;
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
    };
    environment.etc."passwd".text =
      concatStringsSep "\n" (mapAttrsToList mkPasswdLine cfg) + "\n";

    environment.etc."group".text =
      concatStringsSep "\n" (mapAttrsToList mkGroupLine allGroups) + "\n";

    environment.etc."user_control.json".text = builtins.toJSON userControlJson;
  };
}
