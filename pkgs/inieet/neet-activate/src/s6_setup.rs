use crate::user_group::{resolve_gid, resolve_uid};
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::path::PathBuf;
use std::process::Command;

/// /etc/s6-rc/users 配下の全ユーザー用 DB を /var/lib に準備し、
/// 必要に応じて稼働中セッションのホットリロード (s6-rc-update) を行う
pub fn setup_user_s6(is_switch: bool) -> io::Result<()> {
    let etc_users_dir = Path::new("/etc/s6-rc/users");
    if !etc_users_dir.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(etc_users_dir)? {
        let entry = entry?;
        let user_name = entry.file_name().into_string().unwrap_or_default();
        let src_compiled = entry.path().join("compiled");

        if !src_compiled.exists() {
            continue;
        }

        let Some(uid) = resolve_uid(&user_name) else {
            eprintln!("neet-activate: [s6] warning: unknown user {user_name}");
            continue;
        };
        let gid = resolve_gid(&user_name).unwrap_or(uid);

        // 1. /var/lib/s6-rc/users/<user> ディレクトリを確保
        let target_dir = Path::new("/var/lib/s6-rc/users").join(&user_name);
        fs::create_dir_all(&target_dir)?;
        let _ = std::os::unix::fs::chown(&target_dir, Some(uid), Some(gid));

        let dest_compiled = target_dir.join("compiled");

        // 2. 前回の DB があれば削除して、新しい世代の DB をコピー
        if dest_compiled.exists() {
            let _ = fs::remove_dir_all(&dest_compiled);
        }
        copy_dir_recursive(&src_compiled, &dest_compiled)?;

        // 3. Nix store の 0555 を解消！所有者をユーザーにし、u+w を再帰的に付与
        chown_and_chmod_recursive(&dest_compiled, uid, gid)?;

        // 4. switch 時かつセッション稼働中なら、s6-rc-update を実行
        if is_switch {
            let live_dir = PathBuf::from(format!("/run/user/{uid}/s6-rc"));

            if live_dir.exists() {
                println!(
                    "neet-activate: [s6] updating live session for {user_name} (UID: {uid})..."
                );

                // s6-setuidgid でユーザー権限に降格して s6-rc-update
                let status = Command::new("s6-setuidgid")
                    .arg(&user_name)
                    .arg("s6-rc-update")
                    .arg("-l")
                    .arg(&live_dir)
                    .arg(&dest_compiled)
                    .status();

                if let Err(e) = status {
                    eprintln!("neet-activate: [s6] warning: failed to run s6-rc-update: {e}");
                }
            }
        }
    }

    Ok(())
}

/// ディレクトリの再帰的コピー
fn copy_dir_recursive(src: &Path, dst: &Path) -> io::Result<()> {
    fs::create_dir_all(dst)?;
    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let file_type = entry.file_type()?;
        let dest_path = dst.join(entry.file_name());

        if file_type.is_dir() {
            copy_dir_recursive(&entry.path(), &dest_path)?;
        } else if file_type.is_symlink() {
            let target = fs::read_link(entry.path())?;
            let _ = std::os::unix::fs::symlink(target, dest_path);
        } else {
            fs::copy(entry.path(), dest_path)?;
        }
    }
    Ok(())
}

/// 再帰的な chown と u+w 付与（一般ユーザーの DAC エラーを完全防止）
fn chown_and_chmod_recursive(path: &Path, uid: u32, gid: u32) -> io::Result<()> {
    let _ = std::os::unix::fs::chown(path, Some(uid), Some(gid));

    let metadata = fs::symlink_metadata(path)?;
    if !metadata.file_type().is_symlink() {
        let mut mode = metadata.permissions().mode();
        mode |= 0o700; // 所有者に rwx を確約
        let _ = fs::set_permissions(path, fs::Permissions::from_mode(mode));
    }

    if metadata.is_dir() {
        for entry in fs::read_dir(path)? {
            chown_and_chmod_recursive(&entry?.path(), uid, gid)?;
        }
    }
    Ok(())
}
