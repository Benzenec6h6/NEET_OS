//! esp-sync
//!
//! Synchronizes kernel/UKI payloads between Nix profiles and the EFI System Partition (ESP),
//! signs EFI binaries if keys are provided, and garbage-collects obsolete files.

use neet_core::{atomic, generation};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

struct Opts {
    boot_dir: PathBuf,
    profiles_dir: PathBuf,
    key: Option<PathBuf>,
    cert: Option<PathBuf>,
}

fn parse_args() -> Result<Opts, String> {
    let mut args = env::args().skip(1);
    let mut boot_dir = None;
    let mut profiles_dir = PathBuf::from(generation::PROFILES);
    let mut key = None;
    let mut cert = None;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--profiles" => {
                profiles_dir = PathBuf::from(
                    args.next()
                        .ok_or("esp-sync: missing value for --profiles")?,
                );
            }
            "--key" => {
                key = Some(PathBuf::from(
                    args.next().ok_or("esp-sync: missing value for --key")?,
                ));
            }
            "--cert" => {
                cert = Some(PathBuf::from(
                    args.next().ok_or("esp-sync: missing value for --cert")?,
                ));
            }
            "--help" | "-h" => {
                return Err("help".to_string());
            }
            s if !s.starts_with('-') && boot_dir.is_none() => {
                boot_dir = Some(PathBuf::from(s));
            }
            _ => return Err(format!("esp-sync: unexpected argument or option '{arg}'")),
        }
    }

    let boot_dir = boot_dir.ok_or(
        "usage: esp-sync [--profiles <dir>] [--key <db.key>] [--cert <db.crt>] <boot-dir>",
    )?;

    Ok(Opts {
        boot_dir,
        profiles_dir,
        key,
        cert,
    })
}

fn main() -> io::Result<()> {
    let opts = match parse_args() {
        Ok(o) => o,
        Err(msg) => {
            if msg == "help" {
                println!("usage: esp-sync [--profiles <dir>] [--key <db.key>] [--cert <db.crt>] <boot-dir>");
                std::process::exit(0);
            }
            eprintln!("{msg}");
            std::process::exit(1);
        }
    };

    if !opts.boot_dir.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("boot directory does not exist: {}", opts.boot_dir.display()),
        ));
    }

    println!("esp-sync: target ESP at {}", opts.boot_dir.display());

    // 1. 標準ディレクトリの担保
    let efi_linux_dir = opts.boot_dir.join("EFI/Linux");
    let kernels_dir = opts.boot_dir.join("kernels");
    fs::create_dir_all(&efi_linux_dir)?;
    fs::create_dir_all(&kernels_dir)?;

    // 2. neet_core 経由でプロファイルから世代一覧を取得
    println!(
        "esp-sync: scanning profiles at {}",
        opts.profiles_dir.display()
    );
    let (generations, skipped) = generation::list(&opts.profiles_dir)?;
    for (num, err) in skipped {
        eprintln!("esp-sync: warning: skipped generation {num}: {err}");
    }
    println!("esp-sync: found {} generation(s)", generations.len());

    if generations.is_empty() {
        eprintln!(
            "esp-sync: [WARNING] no generations found in {}",
            opts.profiles_dir.display()
        );
        eprintln!("esp-sync: [WARNING] skipping payload installation");
        return Ok(());
    }

    let mut keep_uki_files = HashSet::new();
    let mut keep_kernel_files = HashSet::new();

    // 3. 各世代の boot.json を読み取り、ESP へ配置
    for gen in &generations {
        let Some(spec) = gen.bootspec()? else {
            eprintln!(
                "esp-sync: warning: boot.json not found in {}, skipping generation {}",
                gen.toplevel.display(),
                gen.number
            );
            continue;
        };

        if let Some(ref uki_src) = spec.uki {
            let uki_filename = gen.uki_name();
            let dest = efi_linux_dir.join(&uki_filename);

            neet_core::secureboot::install_and_sign_efi_cached(
                Path::new(uki_src),
                &dest,
                opts.key.as_deref(),
                opts.cert.as_deref(),
                Some("esp-sync"),
            )?;

            keep_uki_files.insert(uki_filename.clone());
            keep_uki_files.insert(format!("{uki_filename}.hash"));
        } else {
            let vmlinuz_filename = gen.kernel_name();
            let dest_kernel = kernels_dir.join(&vmlinuz_filename);
            if atomic::atomic_copy_if_changed(Path::new(&spec.kernel), &dest_kernel, 0o755)? {
                println!("esp-sync: installed {}", dest_kernel.display());
            }
            keep_kernel_files.insert(vmlinuz_filename);

            if let Some(ref initrd_src) = spec.initrd {
                let initrd_filename = gen.initrd_name();
                let dest_initrd = kernels_dir.join(&initrd_filename);
                if atomic::atomic_copy_if_changed(Path::new(initrd_src), &dest_initrd, 0o644)? {
                    println!("esp-sync: installed {}", dest_initrd.display());
                }
                keep_kernel_files.insert(initrd_filename);
            }
        }
    }

    // 4. 古い世代のファイルを安全に削除 (GC)
    let active_gens: HashSet<u32> = generations.iter().map(|g| g.number).collect();

    for removed in neet_core::cleanup::cleanup_stale_generation_files(&efi_linux_dir, &active_gens)?
    {
        println!("esp-sync: removed obsolete file {}", removed.display());
    }
    for removed in neet_core::cleanup::cleanup_stale_generation_files(&kernels_dir, &active_gens)? {
        println!("esp-sync: removed obsolete file {}", removed.display());
    }

    println!("esp-sync: payload sync completed successfully");
    Ok(())
}
