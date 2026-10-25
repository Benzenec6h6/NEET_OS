use crate::user_group::{resolve_gid, resolve_uid};
use neet_core::atomic;
use serde::Deserialize;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

#[derive(Debug, Deserialize)]
pub struct StateDirectory {
    pub path: String,
    pub mode: String,
    pub user: String,
    pub group: String,
}

/// mount-plan.json をロードしてファイルシステムをマウントする
/// マウントの解釈と実行ロジックはすべて neet-mount に委譲
pub fn setup_filesystems(plan_path: &Path) -> io::Result<()> {
    if !plan_path.exists() {
        eprintln!(
            "neet-activate: warning: mount plan not found at {}",
            plan_path.display()
        );
        return Ok(());
    }

    let entries = neet_mount::load_plan(plan_path)?;
    neet_mount::apply_plan(&entries, Path::new("/"), false)?;

    // --- cgroup v2 のコントローラー有効化 ---
    setup_cgroups()?;

    Ok(())
}

/// cgroup v2 のルートコントローラーを子サブツリーに委譲する
fn setup_cgroups() -> io::Result<()> {
    let controllers_path = Path::new("/sys/fs/cgroup/cgroup.controllers");
    let subtree_path = Path::new("/sys/fs/cgroup/cgroup.subtree_control");

    if controllers_path.exists() && subtree_path.exists() {
        if let Ok(controllers) = fs::read_to_string(controllers_path) {
            // 利用可能な全コントローラー（例: "cpu memory pids"）の先頭に "+" を付けて書き込む
            let enable_str = controllers
                .split_whitespace()
                .map(|c| format!("+{c}"))
                .collect::<Vec<_>>()
                .join(" ");

            if !enable_str.is_empty() {
                let _ = fs::write(subtree_path, enable_str);
                println!("neet-activate: cgroup v2 controllers enabled in subtree_control");
            }
        }
    }
    Ok(())
}

/// /etc/state-directories.json をロードして、ディレクトリ作成と権限設定を一括実行
pub fn setup_state_directories() -> io::Result<()> {
    let json_path = Path::new("/etc/state-directories.json");
    if !json_path.exists() {
        return Ok(());
    }

    let content = fs::read_to_string(json_path)?;
    let dirs: Vec<StateDirectory> = serde_json::from_str(&content)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    for dir in dirs {
        let path = Path::new(&dir.path);
        if !path.exists() {
            fs::create_dir_all(path)?;
        }

        let mode = u32::from_str_radix(&dir.mode, 8).unwrap_or(0o755);
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode));

        let uid = resolve_uid(&dir.user);
        let gid = resolve_gid(&dir.group);

        if uid.is_some() || gid.is_some() {
            let _ = std::os::unix::fs::chown(path, uid, gid);
        }
    }
    Ok(())
}

/// 基本的な互換シンボリックリンクや空ログファイルを整える
pub fn setup_base_directories() -> io::Result<()> {
    // 伝統的なアカウンティング / ログ用空ファイルの担保
    let var_log_files: &[(&str, u32)] = &[
        ("/var/log/lastlog", 0o664),
        ("/var/log/wtmp", 0o664),
        ("/var/log/btmp", 0o600),
    ];

    for (file, mode) in var_log_files {
        let path = Path::new(file);
        if !path.exists() {
            let _ = fs::OpenOptions::new()
                .write(true)
                .create_new(true)
                .open(path);
        }
        if path.exists() {
            let _ = fs::set_permissions(path, fs::Permissions::from_mode(*mode));
        }
    }

    // 互換シンボリックリンクの作成
    atomic::atomic_symlink(Path::new("/run"), Path::new("/var/run"))?;
    atomic::atomic_symlink(Path::new("/run/lock"), Path::new("/var/lock"))?;
    atomic::atomic_symlink(Path::new("/bin"), Path::new("/sbin"))?;

    // グラフィックスドライバのリンク
    let gfx = Path::new("/run/current-system/graphics-drivers");
    if gfx.exists() {
        atomic::atomic_symlink(gfx, Path::new("/run/opengl-driver"))?;
    }
    let gfx32 = Path::new("/run/current-system/graphics-drivers-32bit");
    if gfx32.exists() {
        atomic::atomic_symlink(gfx32, Path::new("/run/opengl-driver-32"))?;
    }

    Ok(())
}
