//! UEFI & NVRAM utilities for NEET OS

use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone)]
pub struct EspInfo {
    pub disk: String,      // 例: "/dev/vda", "/dev/nvme0n1"
    pub partition: String, // 例: "1"
}

fn err(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

pub fn is_efivarfs_mounted() -> bool {
    let efivars = Path::new("/sys/firmware/efi/efivars");
    if !efivars.exists() {
        return false;
    }
    fs::read_to_string("/proc/mounts")
        .map(|s| {
            s.lines()
                .any(|l| l.split_whitespace().nth(2) == Some("efivarfs"))
        })
        .unwrap_or(false)
}

pub fn detect_esp(boot_dir: &Path) -> io::Result<EspInfo> {
    let canonical_boot = fs::canonicalize(boot_dir)?;
    let mounts = fs::read_to_string("/proc/mounts")?;

    let mut source = None;
    for line in mounts.lines() {
        let parts: Vec<&str> = line.split_whitespace().collect();
        if parts.len() >= 2 && Path::new(parts[1]) == canonical_boot {
            source = Some(parts[0].to_string());
            break;
        }
    }

    let source = source.ok_or_else(|| {
        err(format!(
            "cannot find mount source for {}",
            boot_dir.display()
        ))
    })?;

    let real_dev = fs::canonicalize(&source)?;
    let dev_name = real_dev
        .file_name()
        .and_then(|n| n.to_str())
        .ok_or_else(|| err(format!("bad device path: {}", real_dev.display())))?;

    let sys_block = Path::new("/sys/class/block").join(dev_name);
    let part_num = fs::read_to_string(sys_block.join("partition"))
        .map_err(|e| err(format!("{} is not a partition: {e}", real_dev.display())))?
        .trim()
        .to_string();

    let disk_dev = fs::canonicalize(&sys_block)?
        .parent()
        .and_then(|p| p.file_name())
        .and_then(|n| n.to_str())
        .map(|n| format!("/dev/{n}"))
        .ok_or_else(|| err("cannot determine parent disk".into()))?;

    Ok(EspInfo {
        disk: disk_dev,
        partition: part_num,
    })
}

/// 現在の NVRAM エントリ一覧を取得 (Label -> BootNumber 文字列)
pub fn list_boot_entries() -> io::Result<HashMap<String, String>> {
    let output = Command::new("efibootmgr").output()?;
    if !output.status.success() {
        return Err(err(format!(
            "efibootmgr failed: {}",
            String::from_utf8_lossy(&output.stderr)
        )));
    }

    let stdout = String::from_utf8_lossy(&output.stdout);
    let mut map = HashMap::new();

    for line in stdout.lines() {
        // 例: "Boot0001* NEET OS (Generation 1)\tHD(1,GPT,...)"
        // または "Boot0001* NEET OS (Generation 1)"
        if let Some(rest) = line.strip_prefix("Boot") {
            let Some(boot_num) = rest
                .split_whitespace()
                .next()
                .map(|s| s.trim_end_matches('*'))
            else {
                continue;
            };

            // "Boot0001* " の後を取得
            let line_rest = rest
                .trim_start_matches(|c: char| c.is_ascii_hexdigit() || c == '*')
                .trim_start();
            let label = if let Some(tab_pos) = line_rest.find('\t') {
                &line_rest[..tab_pos]
            } else {
                line_rest
            }
            .trim();

            if !label.is_empty() {
                map.insert(label.to_string(), boot_num.to_string());
            }
        }
    }
    Ok(map)
}

pub fn has_boot_entry(label_substring: &str) -> bool {
    list_boot_entries()
        .map(|entries| entries.keys().any(|l| l.contains(label_substring)))
        .unwrap_or(false)
}

pub fn create_boot_entry(
    disk: &str,
    part: &str,
    label: &str,
    loader_path: &str,
    extra_args: Option<&str>,
) -> io::Result<()> {
    let mut cmd = Command::new("efibootmgr");
    cmd.args([
        "--create",
        "--disk",
        disk,
        "--part",
        part,
        "--label",
        label,
        "--loader",
        loader_path,
    ]);

    if let Some(args) = extra_args {
        cmd.args(["-u", args]);
    }

    let status = cmd.status()?;
    if !status.success() {
        return Err(err(format!("efibootmgr failed to create entry '{label}'")));
    }
    Ok(())
}

pub fn delete_boot_entry(boot_num: &str) -> io::Result<()> {
    let status = Command::new("efibootmgr")
        .args(["-b", boot_num, "-B"])
        .status()?;
    if !status.success() {
        return Err(err(format!("efibootmgr failed to delete Boot{boot_num}")));
    }
    Ok(())
}
