//! efistub-sync
//!
//! Synchronizes UEFI NVRAM boot entries with current Nix system profiles.
//! Does NOT touch ESP files directly (delegated to esp-sync).

use bootspec::Document;
use neet_core::{generation, uefi};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::Path;

fn err(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: efistub-sync <boot-dir> [disk-device] [part-num]");
        eprintln!("example: efistub-sync /boot");
        eprintln!("     or: efistub-sync /boot /dev/nvme0n1 1");
        std::process::exit(1);
    }

    // 0. efivarfs の確認 (neet-core)
    if !uefi::is_efivarfs_mounted() {
        return Err(err(
            "efivarfs is not mounted at /sys/firmware/efi/efivars!".into()
        ));
    }

    let boot_dir = Path::new(&args[1]);

    // 引数指定がなければ neet-core::uefi::detect_esp で自動検出
    let (disk_dev, part_num) = match (args.get(2), args.get(3)) {
        (Some(d), Some(p)) if !d.is_empty() && !p.is_empty() => (d.clone(), p.clone()),
        _ => {
            let esp = uefi::detect_esp(boot_dir)?;
            println!(
                "efistub-sync: auto-detected disk: {}, partition: {}",
                esp.disk, esp.partition
            );
            (esp.disk, esp.partition)
        }
    };

    // 1. プロファイルから現在存在する世代一覧を取得 (neet-core)
    let (generations, _skipped) = generation::list(Path::new(generation::PROFILES))?;
    if generations.is_empty() {
        eprintln!("efistub-sync: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    // 2. 現在の NVRAM エントリ一覧を取得 (neet-core)
    let existing_entries = uefi::list_boot_entries()?;
    let mut keep_gen_numbers = HashSet::new();

    // 3. 各世代を NVRAM に同期 (不足していれば作成)
    for gen in &generations {
        let gen_num = gen.number;
        keep_gen_numbers.insert(gen_num);

        let boot_json_path = gen.toplevel.join("boot.json");
        if !boot_json_path.exists() {
            continue;
        }

        let json_text = fs::read_to_string(&boot_json_path)?;
        let doc: Document = serde_json::from_str(&json_text)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        let spec = &doc.bootspec;
        let label = format!("NEET OS (Generation {gen_num})");

        // 既に NVRAM に存在する場合はスキップ
        if existing_entries.contains_key(&label) {
            continue;
        }

        if spec.uki.is_some() {
            // --- パターン A: UKI ---
            let uefi_loader_path = format!(r"\EFI\Linux\neet-gen-{gen_num}.efi");
            println!("efistub-sync: creating NVRAM entry for '{label}' (UKI)...");

            uefi::create_boot_entry(&disk_dev, &part_num, &label, &uefi_loader_path, None)?;
        } else {
            // --- パターン B: Raw カーネル ---
            let uefi_loader_path = format!(r"\kernels\neet-gen-{gen_num}-vmlinuz");
            let uefi_initrd_path = format!(r"\kernels\neet-gen-{gen_num}-initrd");

            let cmdline = format!(
                "initrd={} init={} {}",
                uefi_initrd_path,
                spec.init,
                spec.kernel_params.join(" ")
            );

            println!("efistub-sync: creating NVRAM entry for '{label}'...");
            uefi::create_boot_entry(
                &disk_dev,
                &part_num,
                &label,
                &uefi_loader_path,
                Some(&cmdline),
            )?;
        }
    }

    // 4. プロファイルに存在しない古い NVRAM エントリを削除 (NVRAM の GC)
    for (label, boot_num) in existing_entries {
        if let Some(gen_num) = parse_gen_from_label(&label) {
            if !keep_gen_numbers.contains(&gen_num) {
                println!("efistub-sync: removing obsolete NVRAM entry Boot{boot_num} ({label})");
                if let Err(e) = uefi::delete_boot_entry(&boot_num) {
                    eprintln!("efistub-sync: warning: failed to delete Boot{boot_num}: {e}");
                }
            }
        }
    }

    println!("efistub-sync: NVRAM synchronization completed successfully");
    Ok(())
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
