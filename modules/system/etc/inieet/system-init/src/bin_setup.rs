use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::Path;

const BIN_DIR: &str = "/bin";

/// /bin にシステムパッケージをリンクする
pub fn setup_bin(system_path: &Path) -> io::Result<()> {
    println!(
        "system-init: populating /bin from {}",
        system_path.display()
    );
    fs::create_dir_all(BIN_DIR)?;

    let store_bin = system_path.join("bin");
    if !store_bin.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(store_bin)? {
        let entry = entry?;
        let file_name = entry.file_name();
        let dest = Path::new(BIN_DIR).join(&file_name);

        let _ = fs::remove_file(&dest);
        symlink(entry.path(), &dest)?;
    }

    // /bin/system-init が存在する前提で、poweroff / reboot のリンクを作成
    let bin_dir = Path::new(BIN_DIR);
    let system_init = bin_dir.join("system-init");

    for cmd in &["poweroff", "reboot"] {
        let dest = bin_dir.join(cmd);
        let _ = fs::remove_file(&dest);
        symlink(&system_init, &dest)?;
    }

    Ok(())
}
