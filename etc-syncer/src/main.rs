use std::os::unix::fs::symlink;
use std::os::unix::fs::PermissionsExt;
use std::{env, fs, path::Path};

fn main() {
    let args: Vec<String> = env::args().collect();
    let source_dir = args.get(1).expect("Usage: etc-syncer <source_dir>");

    sync_dir(Path::new(source_dir), Path::new("/etc")).expect("Sync failed");
}

fn sync_dir(src: &Path, dst: &Path) -> std::io::Result<()> {
    if !dst.exists() {
        fs::create_dir_all(dst)?;
    }

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let src_path = entry.path();
        let file_name = entry.file_name().into_string().unwrap();

        // 1. .mode ファイル自体は無視する
        if file_name.ends_with(".mode") {
            continue;
        }

        let dst_path = dst.join(&file_name);

        if src_path.is_dir() {
            sync_dir(&src_path, &dst_path)?;
        } else {
            // 2. 対応する .mode ファイルがあるか確認
            let mode_file = src.join(format!("{}.mode", file_name));

            if dst_path.exists() || dst_path.is_symlink() {
                let _ = fs::remove_file(&dst_path);
            }

            if mode_file.exists() {
                // モード指定がある場合: ファイルをコピーして権限を設定
                let mode_str = fs::read_to_string(mode_file)?.trim().to_string();
                let mode = u32::from_str_radix(&mode_str, 8).unwrap_or(0o444);

                fs::copy(&src_path, &dst_path)?;
                fs::set_permissions(&dst_path, fs::Permissions::from_mode(mode))?;
                println!("[Rust] Copied: {} with mode {:o}", dst_path.display(), mode);
            } else {
                // モード指定がない場合: 従来通りシンボリックリンク
                symlink(&src_path, &dst_path)?;
                println!(
                    "[Rust] Linked: {} -> {}",
                    dst_path.display(),
                    src_path.display()
                );
            }
        }
    }
    Ok(())
}
