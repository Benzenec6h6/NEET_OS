use crate::user_group::resolve_uid;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

/// 稼働中のユーザーセッションがあれば、ユーザー権限で DB を同期して s6-rc-update する。
/// ログインしていないユーザーは次回ログイン時に user-session.sh が同期するので何もしない。
pub fn setup_user_s6(is_switch: bool) -> io::Result<()> {
    if !is_switch {
        return Ok(());
    }
    let etc_users_dir = Path::new("/etc/s6-rc/users");
    if !etc_users_dir.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(etc_users_dir)? {
        let entry = entry?;
        let user_name = entry.file_name().into_string().unwrap_or_default();
        if !entry.path().join("compiled").exists() {
            continue;
        }
        let Some(uid) = resolve_uid(&user_name) else {
            eprintln!("neet-activate: [s6] warning: unknown user {user_name}");
            continue;
        };
        let runtime = format!("/run/user/{uid}");
        if !Path::new(&format!("{runtime}/s6-rc")).exists() {
            continue;
        }

        println!("neet-activate: [s6] updating live session for {user_name} (UID: {uid})...");
        let status = Command::new("s6-setuidgid")
            .arg(&user_name)
            .arg("/run/current-system/bin/neet-user-s6-sync")
            .arg("update")
            .env("XDG_RUNTIME_DIR", &runtime)
            .status();
        match status {
            Ok(s) if s.success() => {}
            Ok(s) => eprintln!("neet-activate: [s6] warning: sync for {user_name} exited with {s}"),
            Err(e) => {
                eprintln!("neet-activate: [s6] warning: failed to run sync for {user_name}: {e}")
            }
        }
    }
    Ok(())
}
