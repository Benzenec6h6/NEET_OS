use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::Path;

/// カーネルモジュールのセットアップ
pub fn setup_kernel_modules(kernel_path: &Path) -> io::Result<()> {
    println!("system-init: setting up /lib/modules...");

    let lib_dir = Path::new("/lib");
    if !lib_dir.exists() {
        fs::create_dir_all(lib_dir)?;
    }

    let dest = Path::new("/lib/modules");
    let src = kernel_path.join("lib/modules");

    // ガード節: ソースが存在しなければ早期リターン
    if !src.exists() {
        eprintln!(
            "system-init: warning: kernel modules source not found at {}",
            src.display()
        );
        return Ok(());
    }

    // 既存の dest の削除処理（条件分岐のネストを平坦化）
    if dest.is_symlink() || dest.is_file() {
        fs::remove_file(dest)?;
    } else if dest.is_dir() {
        fs::remove_dir_all(dest)?;
    }

    symlink(&src, dest)?;
    println!("system-init: linked /lib/modules to {}", src.display());

    Ok(())
}
