use std::collections::HashMap;
use std::fs;
use std::io;
use std::os::unix::fs::symlink;
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

/// 基本的なシステムディレクトリと互換シンボリックリンクを整える
pub fn setup_base_directories() -> io::Result<()> {
    // 1. /var 配下の永続ディレクトリの準備
    let var_dirs = ["/var/db", "/var/lib", "/var/log"];
    for dir in &var_dirs {
        fs::create_dir_all(dir)?;
    }

    // 2. /run 配下の一時ディレクトリの準備
    let run_dirs = ["/run/lock"];
    for dir in &run_dirs {
        let path = Path::new(dir);
        if !path.exists() {
            fs::create_dir_all(path)?;
            // ロックディレクトリは 1777 (sticky bit) が標準
            let _ = fs::set_permissions(path, fs::Permissions::from_mode(0o1777));
        }
    }

    // 3. 互換シンボリックリンクの作成
    //    (壊れたリンクが残っていても安全に作り直す)
    ensure_symlink(Path::new("/run"), Path::new("/var/run"))?;
    ensure_symlink(Path::new("/run/lock"), Path::new("/var/lock"))?;

    // (オプション) /sbin を使おうとする古いツール向け
    ensure_symlink(Path::new("/bin"), Path::new("/sbin"))?;

    Ok(())
}

/// 既存のファイル/壊れたリンクを安全に削除してシンボリックリンクを保証するヘルパー
fn ensure_symlink(src: &Path, dest: &Path) -> io::Result<()> {
    if dest.is_symlink() || dest.exists() {
        let _ = fs::remove_file(dest);
    }
    // ディレクトリとして実体が存在してしまっている場合は削除できないため回避
    if !dest.exists() {
        symlink(src, dest)?;
    }
    Ok(())
}
