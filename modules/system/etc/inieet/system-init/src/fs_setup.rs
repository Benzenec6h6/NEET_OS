use std::collections::HashMap;
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use nix::unistd::chown;
use serde::Deserialize;

use crate::etc_syncer::user_group::UserEntry;

#[derive(Debug, Deserialize)]
struct UserControl {
    username: String,
    #[serde(rename = "createHome")]
    create_home: bool,
    #[serde(rename = "createRuntimeDir")]
    create_runtime_dir: bool,
}

/// mount-plan.json をロードしてファイルシステムをマウントする
/// マウントの解釈と実行ロジックはすべて init-core に委譲
pub fn setup_filesystems(plan_path: &Path) -> io::Result<()> {
    if !plan_path.exists() {
        eprintln!(
            "system-init: warning: mount plan not found at {}",
            plan_path.display()
        );
        return Ok(());
    }

    // init-core 側で JSON をロード・深さ順ソートして読み込む
    let entries = init_core::load_plan(plan_path)?;

    // stage2 ではルート（"/"）に対してプランを適用
    init_core::apply_plan(&entries, Path::new("/"))
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
