use neet_core::{generation, uefi};
use std::collections::HashSet;
use std::env;
use std::io;
use std::path::{Path, PathBuf};

struct Opts {
    boot_dir: PathBuf,
    disk_dev: Option<String>,
    part_num: Option<String>,
    max_generations: Option<usize>,
}

fn err(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

fn parse_args() -> Result<Opts, String> {
    let mut args = env::args().skip(1);
    let mut positional = Vec::new();
    let mut max_generations = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--max-generations" => {
                let val = args
                    .next()
                    .ok_or("efistub-sync: missing value for --max-generations")?;
                let n = val
                    .parse::<usize>()
                    .map_err(|e| format!("efistub-sync: invalid --max-generations '{val}': {e}"))?;
                if n == 0 {
                    return Err("efistub-sync: --max-generations must be >= 1".to_string());
                }
                max_generations = Some(n);
            }
            s if !s.starts_with('-') => positional.push(s.to_string()),
            _ => return Err(format!("efistub-sync: unexpected argument '{arg}'")),
        }
    }

    if positional.is_empty() || positional.len() > 3 {
        return Err(
            "usage: efistub-sync [--max-generations <N>] <boot-dir> [disk-device] [part-num]"
                .to_string(),
        );
    }

    Ok(Opts {
        boot_dir: PathBuf::from(&positional[0]),
        disk_dev: positional.get(1).filter(|s| !s.is_empty()).cloned(),
        part_num: positional.get(2).filter(|s| !s.is_empty()).cloned(),
        max_generations,
    })
}

fn main() -> io::Result<()> {
    let opts = parse_args().map_err(err)?;

    if !uefi::is_efivarfs_mounted() {
        return Err(err(
            "efivarfs is not mounted at /sys/firmware/efi/efivars!".into()
        ));
    }

    let (disk_dev, part_num) = match (opts.disk_dev, opts.part_num) {
        (Some(d), Some(p)) => (d, p),
        _ => {
            let esp = uefi::detect_esp(&opts.boot_dir)?;
            println!(
                "efistub-sync: auto-detected disk: {}, partition: {}",
                esp.disk, esp.partition
            );
            (esp.disk, esp.partition)
        }
    };

    // 1. プロファイルから世代一覧を取得（上限適用）
    let (generations, _skipped) =
        generation::list_limited(Path::new(generation::PROFILES), opts.max_generations)?;
    if generations.is_empty() {
        eprintln!("efistub-sync: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    // 2. 古い NVRAM エントリを先に削除 (NVRAM の GC)
    let active_gens: HashSet<u32> = generations.iter().map(|g| g.number).collect();
    let removed = neet_core::cleanup::cleanup_stale_nvram_entries(&active_gens)?;
    for (label, boot_num) in removed {
        println!("efistub-sync: removed obsolete NVRAM entry Boot{boot_num} ({label})");
    }

    // 3. 現在の NVRAM エントリ一覧を取得して不足分を作成
    let existing_entries = uefi::list_boot_entries()?;

    for gen in &generations {
        let Some(spec) = gen.bootspec()? else {
            continue;
        };

        let label = gen.label();
        if existing_entries.contains_key(&label) {
            continue;
        }

        if spec.uki.is_some() {
            let uki_path = opts.boot_dir.join("EFI/Linux").join(gen.uki_name());
            if !uki_path.exists() {
                eprintln!(
                    "efistub-sync: warning: {} missing on ESP, skipping NVRAM entry for generation {}",
                    uki_path.display(),
                    gen.number
                );
                continue;
            }
            let uefi_loader_path = format!(r"\EFI\Linux\{}", gen.uki_name());
            println!("efistub-sync: creating NVRAM entry for '{label}' (UKI)...");
            uefi::create_boot_entry(&disk_dev, &part_num, &label, &uefi_loader_path, None)?;
        } else {
            let kernel_path = opts.boot_dir.join("kernels").join(gen.kernel_name());
            if !kernel_path.exists() {
                eprintln!(
                    "efistub-sync: warning: {} missing on ESP, skipping NVRAM entry for generation {}",
                    kernel_path.display(),
                    gen.number
                );
                continue;
            }
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

    println!("efistub-sync: NVRAM synchronization completed successfully");
    Ok(())
}
