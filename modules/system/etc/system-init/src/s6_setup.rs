use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::Path;

const SERVICE_SRC: &str = "/etc/s6-scan";
const SERVICE_DEST: &str = "/run/service";

/// s6-scan ディレクトリを /run/service に準備する
pub fn setup_s6_services() -> io::Result<()> {
    let src = Path::new(SERVICE_SRC);
    let dest = Path::new(SERVICE_DEST);

    if !src.exists() {
        return Ok(());
    }

    println!("system-init: preparing s6 services in {}", dest.display());
    let _ = fs::remove_dir_all(dest);
    fs::create_dir_all(dest)?;

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let name = entry.file_name();
        let service_dest = dest.join(name);

        symlink(entry.path(), service_dest)?;
    }
    Ok(())
}
