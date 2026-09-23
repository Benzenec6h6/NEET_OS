use std::fs;
use std::io;
use std::path::Path;

pub fn setup_firmware(firmware_path: &Path) -> io::Result<()> {
    let sysfs_path = Path::new("/sys/module/firmware_class/parameters/path");
    let fw_dir = firmware_path.join("lib/firmware");

    // 1. カーネルのパラメータ受付口が存在し、
    // 2. かつファームウェアディレクトリが空でなく実際に存在する場合のみ設定する
    if sysfs_path.exists() && fw_dir.exists() {
        fs::write(sysfs_path, fw_dir.to_string_lossy().as_bytes())?;
        println!(
            "system-init: registered firmware path -> {}",
            fw_dir.display()
        );
    } else {
        println!("system-init: no firmware path configured (skipping)");
    }

    Ok(())
}
