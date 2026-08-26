use std::fs;
use std::io;
use std::path::Path;

/// 指定された設定ファイル (/etc/network/up_interfaces) に書かれた
/// インターフェースのみを UP にする
pub fn setup_existing_network() -> io::Result<()> {
    let config_path = Path::new("/etc/network/up_interfaces");
    if !config_path.exists() {
        // 設定ファイルがない場合は安全のためスキップ
        return Ok(());
    }

    // 設定ファイルから対象のインターフェース名を読み取る
    let content = fs::read_to_string(config_path)?;
    let target_interfaces: Vec<&str> = content
        .lines()
        .map(|line| line.trim())
        .filter(|line| !line.is_empty() && !line.starts_with('#'))
        .collect();

    for iface in target_interfaces {
        let flags_path = Path::new("/sys/class/net").join(iface).join("flags");

        if flags_path.exists() {
            if let Ok(flags_str) = fs::read_to_string(&flags_path) {
                let trimmed = flags_str.trim().trim_start_matches("0x");
                if let Ok(mut flags) = u32::from_str_radix(trimmed, 16) {
                    // フラグの 0x1 (IFF_UP) を立てて書き直す
                    if (flags & 0x1) == 0 {
                        flags |= 0x1;
                        if let Err(e) = fs::write(&flags_path, format!("{:#x}\n", flags)) {
                            eprintln!("system-init: warning: failed to bring up {}: {}", iface, e);
                        } else {
                            println!("system-init: brought up network interface: {}", iface);
                        }
                    }
                }
            }
        } else {
            eprintln!(
                "system-init: warning: interface {} not found in sysfs",
                iface
            );
        }
    }

    Ok(())
}
