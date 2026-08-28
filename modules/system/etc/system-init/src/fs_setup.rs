use crate::etc_syncer::user_group::UserEntry;
use nix::mount::{mount, MsFlags};
use nix::unistd::chown;
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

#[derive(Debug, Deserialize)]
pub struct MountEntry {
    pub device: String,
    #[serde(rename = "mountPoint")]
    pub mount_point: String,
    #[serde(rename = "fsType")]
    pub fs_type: String,
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(rename = "neededForBoot", default)]
    pub needed_for_boot: bool,
    #[serde(default)]
    pub dump: u32,
    #[serde(default)]
    pub pass: u32,
}

#[derive(Debug, Deserialize)]
struct UserControl {
    username: String,
    #[serde(rename = "createHome")]
    create_home: bool,
    #[serde(rename = "createRuntimeDir")]
    create_runtime_dir: bool,
}

/// ユーザーディレクトリ群（/home/<user>, /run/user/<uid>）の設定
pub fn setup_user_directories(users: &[UserEntry]) -> io::Result<()> {
    let control_map: HashMap<String, UserControl> = fs::read_to_string("/etc/user_control.json")
        .ok()
        .and_then(|data| serde_json::from_str::<Vec<UserControl>>(&data).ok())
        .map(|list| list.into_iter().map(|c| (c.username.clone(), c)).collect())
        .unwrap_or_default();

    for user in users {
        let (create_home, create_runtime) = control_map
            .get(&user.username)
            .map(|c| (c.create_home, c.create_runtime_dir))
            .unwrap_or((true, true));

        // 1. ホームディレクトリの生成と所有権変更
        if create_home {
            setup_single_directory(
                Path::new(&user.home),
                user,
                0o755,
                &format!("creating home dir for {} at {}", user.username, user.home),
            )?;
        }

        // 2. 一般ユーザー(UID >= 1000)に対する XDG_RUNTIME_DIR の生成
        if user.uid.as_raw() >= 1000 && create_runtime {
            let runtime_path_str = format!("/run/user/{}", user.uid.as_raw());
            setup_single_directory(
                Path::new(&runtime_path_str),
                user,
                0o700,
                &format!("creating XDG_RUNTIME_DIR at {}", runtime_path_str),
            )?;
        }
    }
    Ok(())
}

/// ディレクトリが存在しない場合のみ作成し、パーミッションを設定するヘルパー
fn setup_single_directory(
    path: &Path,
    user: &UserEntry,
    mode: u32,
    log_msg: &str,
) -> io::Result<()> {
    if path.exists() {
        return Ok(());
    }

    println!("system-init: {}", log_msg);
    fs::create_dir_all(path)?;
    let _ = chown(path, Some(user.uid), Some(user.gid));
    let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode));
    Ok(())
}

/// mount-plan.json をロードしてファイルシステムをマウント
pub fn setup_filesystems(plan_path: &Path, early_only: bool) -> io::Result<()> {
    if !plan_path.exists() {
        eprintln!(
            "system-init: warning: mount plan not found at {}",
            plan_path.display()
        );
        return Ok(());
    }

    let data = fs::read_to_string(plan_path)?;
    let plan: HashMap<String, MountEntry> =
        serde_json::from_str(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    // マウント順序制御: パス文字列長昇順ソート（/ が最優先され、ネストしたパスが後に続く）
    let mut entries: Vec<&MountEntry> = plan.values().collect();
    entries.sort_by_key(|e| (e.mount_point.len(), e.mount_point.clone()));

    for entry in entries {
        // ガード節: boot時に不要なものをスキップ
        if early_only && !entry.needed_for_boot {
            continue;
        }

        println!(
            "system-init: mounting {} on {} ({})",
            entry.device, entry.mount_point, entry.fs_type
        );

        // マウントターゲットディレクトリが存在しない場合は作成
        if let Err(e) = fs::create_dir_all(&entry.mount_point) {
            eprintln!(
                "system-init: warning: failed to create mount point {}: {}",
                entry.mount_point, e
            );
            continue;
        }

        let (flags, data_options) = parse_mount_options(&entry.options);
        let data_str = (!data_options.is_empty()).then(|| data_options.join(","));

        // マウント実行（EBUSY 以外のエラーのみ出力）
        let result = mount(
            Some(entry.device.as_str()),
            entry.mount_point.as_str(),
            Some(entry.fs_type.as_str()),
            flags,
            data_str.as_deref(),
        );

        if let Err(e) = result {
            if e != nix::errno::Errno::EBUSY {
                eprintln!(
                    "system-init: warning: failed to mount {} ({}): {}",
                    entry.mount_point, entry.device, e
                );
            }
        }
    }

    Ok(())
}

/// fstab形式の文字列オプション配列から MsFlags と データ引数用文字列リストを分離・構築
fn parse_mount_options(options: &[String]) -> (MsFlags, Vec<&str>) {
    let mut flags = MsFlags::empty();
    let mut data_options = Vec::new();

    for opt in options {
        let opt_str = opt.as_str();
        match opt_str {
            "defaults" => (),
            "ro" => flags |= MsFlags::MS_RDONLY,
            "rw" => flags &= !MsFlags::MS_RDONLY,
            "nosuid" => flags |= MsFlags::MS_NOSUID,
            "suid" => flags &= !MsFlags::MS_NOSUID,
            "nodev" => flags |= MsFlags::MS_NODEV,
            "dev" => flags &= !MsFlags::MS_NODEV,
            "noexec" => flags |= MsFlags::MS_NOEXEC,
            "exec" => flags &= !MsFlags::MS_NOEXEC,
            "sync" => flags |= MsFlags::MS_SYNCHRONOUS,
            "async" => flags &= !MsFlags::MS_SYNCHRONOUS,
            "remount" => flags |= MsFlags::MS_REMOUNT,
            "bind" => flags |= MsFlags::MS_BIND,
            "dirsync" => flags |= MsFlags::MS_DIRSYNC,
            "mand" => flags |= MsFlags::MS_MANDLOCK,
            "noatime" => flags |= MsFlags::MS_NOATIME,
            "nodiratime" => flags |= MsFlags::MS_NODIRATIME,
            "relatime" => flags |= MsFlags::MS_RELATIME,
            "strictatime" => flags |= MsFlags::MS_STRICTATIME,
            _ => data_options.push(opt_str),
        }
    }

    (flags, data_options)
}
