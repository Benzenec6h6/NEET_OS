use std::fs;
use std::io;
use std::path::Path;

const CONFIG_PATH: &str = "/etc/network/up_interfaces";
const SYSFS_NET: &str = "/sys/class/net";
const IFF_UP: u32 = 0x1;

pub fn setup_existing_network() -> io::Result<()> {
    let config_path = Path::new(CONFIG_PATH);
    if !config_path.exists() {
        return Ok(());
    }

    let content = fs::read_to_string(config_path)?;
    let interfaces = content
        .lines()
        .map(str::trim)
        .filter(|line| !line.is_empty() && !line.starts_with('#'));

    for iface in interfaces {
        if let Err(e) = bring_up(iface) {
            eprintln!("system-init: warning: failed to bring up {iface}: {e}");
        }
    }

    Ok(())
}

/// 1つのインターフェースを IFF_UP フラグ経由で UP にする。
/// 既に UP なら何もしない。
fn bring_up(iface: &str) -> io::Result<()> {
    let flags_path = Path::new(SYSFS_NET).join(iface).join("flags");

    let flags_str = fs::read_to_string(&flags_path).map_err(|e| {
        io::Error::new(
            e.kind(),
            format!("interface {iface} not found in sysfs ({e})"),
        )
    })?;

    let flags = parse_hex_flags(&flags_str)?;

    if flags & IFF_UP != 0 {
        // すでに UP なので何もしない
        return Ok(());
    }

    fs::write(&flags_path, format!("{:#x}\n", flags | IFF_UP))?;
    println!("system-init: brought up network interface: {iface}");
    Ok(())
}

fn parse_hex_flags(s: &str) -> io::Result<u32> {
    let trimmed = s.trim().trim_start_matches("0x");
    u32::from_str_radix(trimmed, 16)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, format!("bad flags value: {e}")))
}
