//! efistub-sync
//!
//! Synchronizes UEFI NVRAM boot entries with current Nix system profiles.
//! Does NOT touch ESP files directly (delegated to esp-sync).

use bootspec::Document;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

fn err(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

/// /proc/mounts を確認して efivarfs がマウントされているか判定
fn efivarfs_mounted() -> bool {
    fs::read_to_string("/proc/mounts")
        .map(|s| {
            s.lines()
                .any(|l| l.split_whitespace().nth(2) == Some("efivarfs"))
        })
        .unwrap_or(false)
}

/// boot_dir のマウント元から (親ディスク, パーティション番号) を自己完結で取得
fn detect_esp(boot_dir: &Path) -> io::Result<(String, String)> {
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

    Ok((disk_dev, part_num))
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: efistub-sync <boot-dir> [disk-device] [part-num]");
        eprintln!("example: efistub-sync /boot");
        eprintln!("     or: efistub-sync /boot /dev/nvme0n1 1");
        std::process::exit(1);
    }

    // 0. efivarfs の確認
    if !efivarfs_mounted() {
        return Err(err(
            "efivarfs is not mounted at /sys/firmware/efi/efivars!".into()
        ));
    }

    let boot_dir = Path::new(&args[1]);

    let (disk_dev, part_num) = match (args.get(2), args.get(3)) {
        (Some(d), Some(p)) if !d.is_empty() && !p.is_empty() => (d.clone(), p.clone()),
        _ => {
            let (d, p) = detect_esp(boot_dir)?;
            println!("efistub-sync: auto-detected disk: {d}, partition: {p}");
            (d, p)
        }
    };

    // 1. プロファイルから現在存在する世代一覧を取得
    let generations = get_generations()?;
    if generations.is_empty() {
        eprintln!("efistub-sync: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    // 2. 現在の NVRAM エントリ一覧を取得
    let existing_entries = get_current_nvram_entries()?;
    let mut keep_gen_numbers = HashSet::new();

    // 3. 各世代を NVRAM に同期 (不足していれば作成)
    for gen in &generations {
        let gen_num = gen.number;
        keep_gen_numbers.insert(gen_num);

        let boot_json_path = gen.path.join("boot.json");
        if !boot_json_path.exists() {
            continue;
        }

        let json_text = fs::read_to_string(&boot_json_path)?;
        let doc: Document = serde_json::from_str(&json_text)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        let spec = &doc.bootspec;
        let label = format!("NEET OS (Generation {gen_num})");

        if existing_entries.contains_key(&label) {
            continue;
        }

        if spec.uki.is_some() {
            // --- パターン A: UKI (引数不要) ---
            let uefi_loader_path = format!(r"\EFI\Linux\neet-gen-{gen_num}.efi");
            println!("efistub-sync: creating NVRAM entry for '{label}' (UKI)...");

            let status = Command::new("efibootmgr")
                .args([
                    "--create",
                    "--disk",
                    &disk_dev,
                    "--part",
                    &part_num,
                    "--label",
                    &label,
                    "--loader",
                    &uefi_loader_path,
                ])
                .status()?;

            if !status.success() {
                eprintln!("efistub-sync: warning: failed to create boot entry via efibootmgr");
            }
        } else {
            // --- パターン B: Raw カーネル (initrd と cmdline を引数で渡す) ---
            let uefi_loader_path = format!(r"\kernels\neet-gen-{gen_num}-vmlinuz");
            let uefi_initrd_path = format!(r"\kernels\neet-gen-{gen_num}-initrd");

            let cmdline = format!(
                "initrd={} init={} {}",
                uefi_initrd_path,
                spec.init,
                spec.kernel_params.join(" ")
            );

            println!("efistub-sync: creating NVRAM entry for '{label}'...");
            let status = Command::new("efibootmgr")
                .args([
                    "--create",
                    "--disk",
                    &disk_dev,
                    "--part",
                    &part_num,
                    "--label",
                    &label,
                    "--loader",
                    &uefi_loader_path,
                    "-u",
                    &cmdline,
                ])
                .status()?;

            if !status.success() {
                eprintln!("efistub-sync: warning: failed to create boot entry via efibootmgr");
            }
        }
    }

    // 4. プロファイルに存在しない古い NVRAM エントリを削除 (NVRAM の GC)
    for (label, boot_num) in existing_entries {
        if let Some(gen_num) = parse_gen_from_label(&label) {
            if !keep_gen_numbers.contains(&gen_num) {
                println!("efistub-sync: removing obsolete NVRAM entry Boot{boot_num} ({label})");
                let status = Command::new("efibootmgr")
                    .args(["-b", &boot_num, "-B"])
                    .status();

                if let Err(e) = status {
                    eprintln!("efistub-sync: warning: failed to delete Boot{boot_num}: {e}");
                }
            }
        }
    }

    println!("efistub-sync: NVRAM synchronization completed successfully");
    Ok(())
}

struct Generation {
    number: u32,
    path: PathBuf,
}

fn get_generations() -> io::Result<Vec<Generation>> {
    let profiles_dir = Path::new("/nix/var/nix/profiles");
    let mut gens = Vec::new();
    if !profiles_dir.exists() {
        return Ok(gens);
    }
    for entry in fs::read_dir(profiles_dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if name.starts_with("system-") && name.ends_with("-link") {
            let num_part = &name["system-".len()..name.len() - "-link".len()];
            if let Ok(num) = num_part.parse::<u32>() {
                gens.push(Generation {
                    number: num,
                    path: fs::canonicalize(entry.path())?,
                });
            }
        }
    }
    gens.sort_by(|a, b| b.number.cmp(&a.number));
    Ok(gens)
}

fn get_current_nvram_entries() -> io::Result<std::collections::HashMap<String, String>> {
    let mut map = std::collections::HashMap::new();
    let output = Command::new("efibootmgr").output()?;
    let stdout = String::from_utf8_lossy(&output.stdout);

    for line in stdout.lines() {
        if line.starts_with("Boot") && line.contains("NEET OS (Generation ") {
            let parts: Vec<&str> = line.split_whitespace().collect();
            if parts.len() >= 2 {
                let boot_num = parts[0].trim_start_matches("Boot").trim_end_matches('*');
                let label_start = line.find("NEET OS").unwrap_or(0);
                let label_end = line.find('\t').unwrap_or(line.len());
                let label = line[label_start..label_end].trim().to_string();
                map.insert(label, boot_num.to_string());
            }
        }
    }
    Ok(map)
}

fn parse_gen_from_label(label: &str) -> Option<u32> {
    if let Some(start) = label.find("(Generation ") {
        let rest = &label[start + "(Generation ".len()..];
        if let Some(end) = rest.find(')') {
            return rest[..end].parse().ok();
        }
    }
    None
}
