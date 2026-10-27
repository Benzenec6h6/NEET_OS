//! efistub-sync
//!
//! Synchronizes UEFI NVRAM boot entries with current Nix system profiles.
//! Does NOT touch ESP files directly (delegated to esp-sync).

use neet_core::{generation, uefi};
use std::collections::HashSet;
use std::env;
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
        let Some(spec) = gen.bootspec()? else {
            continue;
        };

        keep_gen_numbers.insert(gen.number);
        let label = gen.label();

        if existing_entries.contains_key(&label) {
            continue;
        }

        if spec.uki.is_some() {
            let uefi_loader_path = format!(r"\EFI\Linux\{}", gen.uki_name());
            println!("efistub-sync: creating NVRAM entry for '{label}' (UKI)...");
            uefi::create_boot_entry(&disk_dev, &part_num, &label, &uefi_loader_path, None)?;
        } else {
            let uefi_loader_path = format!(r"\kernels\{}", gen.kernel_name());
            let uefi_initrd_path = format!(r"\kernels\{}", gen.initrd_name());
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
    let active_gens: HashSet<u32> = generations.iter().map(|g| g.number).collect();
    let removed = neet_core::cleanup::cleanup_stale_nvram_entries(&active_gens)?;
    for (label, boot_num) in removed {
        println!("efistub-sync: removed obsolete NVRAM entry Boot{boot_num} ({label})");
    }

    println!("efistub-sync: NVRAM synchronization completed successfully");
    Ok(())
}
