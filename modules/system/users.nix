{
  config,
  lib,
  pkgs,
  ...
}:
with lib; let
  cfg = config.neet.users;

  # etc.nix と同様の汎用ファイル配置オプション
  fileOpts = {
    name,
    config,
    ...
  }: {
    options = {
      text = mkOption {
        type = types.nullOr types.lines;
        default = null;
      };
      source = mkOption {
        type = types.path;
      };
      target = mkOption {
        type = types.str;
        default = name;
        description = "ユーザーホーム ($HOME) からの相対パス";
      };
    };
    config.source = mkIf (config.text != null) (pkgs.writeText "user-file-${name}" config.text);
  };

  # ユーザーの基底オプション
  userOpts = {
    name,
    config,
    options,
    ...
  }: {
    options = {
      assertions = mkOption {
        type = types.listOf types.unspecified;
        default = [];
        internal = true;
        description = "ユーザー '${name}' 設定のアサーション一覧";
      };
      warnings = mkOption {
        type = types.listOf types.str;
        default = [];
        internal = true;
        description = "ユーザー '${name}' 設定の警告一覧";
      };
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
      };
      home = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      createHome = mkOption {
        type = types.bool;
        default = true;
      };
      createRuntimeDir = mkOption {
        type = types.bool;
        default = true;
      };

      # このユーザーがログインセッション・ランタイムサービスを持つか
      isSessionUser = mkOption {
        type = types.bool;
        default = config.createRuntimeDir && (options.uid.isDefined && config.uid >= 1000);
        defaultText = literalExpression "config.createRuntimeDir && config.uid >= 1000";
        description = "ログインしてユーザーセッション・s6サービスを実行する人間ユーザーかどうか";
      };

      description = mkOption {
        type = types.str;
        default = "";
      };
      extraGroups = mkOption {
        type = types.listOf types.str;
        default = [];
      };
      initialHashedPassword = mkOption {
        type = types.nullOr types.str;
        default = null;
      };
      hashedPasswordSecret = mkOption {
        type = types.nullOr types.str;
        default = null;
      };

      # ★ 汎用: ユーザー固有 s6-rc サービス定義 (s6.services に配置)
      s6.services = mkOption {
        type = types.attrsOf types.attrs;
        default = {};
        description = "ユーザー '${name}' の s6-rc サービス定義";
      };

      # 汎用: ホームディレクトリ直下のファイル配置
      files = mkOption {
        type = types.attrsOf (types.submodule fileOpts);
        default = {};
        description = "ユーザーホーム直下に配置するファイル群";
      };

      # 汎用: ~/.config 配下のファイル配置ショートカット
      xdg.configFile = mkOption {
        type = types.attrsOf (types.submodule fileOpts);
        default = {};
        description = "~/.config 配下に配置するファイル群";
      };
    };

    config = {
      files =
        mapAttrs' (
          k: v:
            nameValuePair ".config/${k}" {
              source = v.source;
              target = ".config/${v.target}";
            }
        )
        config.xdg.configFile;
    };
  };

  # ストア上に各ユーザーの配置ファイルツリーを構築
  mkUserStaticFiles = name: u:
    pkgs.runCommand "user-${name}-static-files" {} ''
      mkdir -p $out
      ${concatStringsSep "\n" (mapAttrsToList (_: f: ''
          mkdir -p "$out/$(dirname "${f.target}")"
          ln -s "${f.source}" "$out/${f.target}"
        '')
        u.files)}
    '';

  # /etc/passwd, /etc/group 生成
  mkPasswdLine = name: u: let
    homeDir =
      if u.home != null
      then u.home
      else "/home/${name}";
  in "${name}:x:${toString u.uid}:${toString u.gid}:${u.description}:${homeDir}:${u.shell}";

  sharedGids = attrValues config.neet.gids;
  userGroups = filterAttrs (_name: gid: !elem gid sharedGids) (mapAttrs (_name: u: u.gid) cfg);
  allGroups = config.neet.gids // userGroups;

  getUsersInGroup = groupName: gid:
    attrNames (filterAttrs (
        username: userCfg:
          elem groupName userCfg.extraGroups || (hasAttr groupName config.neet.gids && userCfg.gid == gid)
      )
      cfg);

  mkGroupLine = groupName: gid: let
    members = getUsersInGroup groupName gid;
  in "${groupName}:x:${toString gid}:${concatStringsSep "," members}";

  userDirectories = concatLists (mapAttrsToList (
      name: u: let
        homePath =
          if u.home != null
          then u.home
          else "/home/${name}";
        owner = {
          user = name;
          group = toString u.gid;
        };
      in
        optional u.createHome ({
            path = homePath;
            mode = "0755";
          }
          // owner)
        ++ optionals (u.createHome && u.isSessionUser) [
          ({
              path = "${homePath}/.local/state/log";
              mode = "0700";
            }
            // owner)
        ]
        ++ optional u.isSessionUser ({
            path = "/run/user/${toString u.uid}";
            mode = "0700";
          }
          // owner)
    )
    cfg);
in {
  options.neet = {
    users = mkOption {
      type = types.attrsOf (types.submodule userOpts);
      default = {};
      description = "User definitions for NEET_OS";
    };

    gids = mkOption {
      type = types.attrsOf types.int;
      default = {};
    };

    sessionUsers = mkOption {
      type = types.attrsOf types.attrs;
      internal = true;
      readOnly = true;
      default = filterAttrs (_name: u: u.isSessionUser) cfg;
    };
  };

  config = {
    assertions = concatMap (u: u.assertions) (attrValues cfg);
    warnings = concatMap (u: u.warnings) (attrValues cfg);

    neet.gids = {
      root = lib.mkDefault 0;
      tty = lib.mkDefault 5;
      wheel = lib.mkDefault 10;
      video = lib.mkDefault 44;
      input = lib.mkDefault 104;
      audio = lib.mkDefault 29;
    };

    environment.etc =
      {
        "passwd".text = concatStringsSep "\n" (mapAttrsToList mkPasswdLine cfg) + "\n";
        "group".text = concatStringsSep "\n" (mapAttrsToList mkGroupLine allGroups) + "\n";
      }
      // mapAttrs' (
        name: u:
          nameValuePair "users/${name}/files" {
            source = mkUserStaticFiles name u;
          }
      ) (filterAttrs (_: u: u.files != {}) cfg);
    system.stateDirectories = userDirectories;

    # ★ 各ユーザーの s6.services を s6-rc に接続
    system.s6-rc.users =
      mapAttrs (_: u: {
        services = u.s6.services;
      })
      cfg;
  };
}
