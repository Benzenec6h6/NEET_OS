//! esp-sync
//!
//! Synchronizes kernel/UKI payloads between Nix profiles and the EFI System Partition (ESP),
//! signs EFI binaries if keys are provided, and garbage-collects obsolete files.

use bootspec::Document;
use neet_core::{atomic, generation};
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

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

    if key.is_none() {
        if let Ok(k) = env::var("SECUREBOOT_KEY") {
            key = Some(PathBuf::from(k));
        }
    }
    if cert.is_none() {
        if let Ok(c) = env::var("SECUREBOOT_CERT") {
            cert = Some(PathBuf::from(c));
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
        let gen_num = gen.number;
        let boot_json_path = gen.toplevel.join("boot.json");

        if !boot_json_path.exists() {
            eprintln!(
                "esp-sync: warning: boot.json not found in {}, skipping generation {gen_num}",
                gen.toplevel.display()
            );
            continue;
        }

        let json_str = fs::read_to_string(&boot_json_path)?;
        let doc: Document = serde_json::from_str(&json_str).map_err(|e| {
            io::Error::new(
                io::ErrorKind::InvalidData,
                format!("failed to parse {}: {e}", boot_json_path.display()),
            )
        })?;

        let spec = doc.bootspec;

        if let Some(ref uki_src) = spec.uki {
            // ==========================================
            // パターン A: UKI (署名対応 / .hash 方式)
            // ==========================================
            let uki_filename = format!("neet-gen-{gen_num}.efi");
            let dest = efi_linux_dir.join(&uki_filename);

            install_uki_if_changed(
                Path::new(uki_src),
                &dest,
                opts.key.as_deref(),
                opts.cert.as_deref(),
            )?;

            keep_uki_files.insert(uki_filename.clone());
            keep_uki_files.insert(format!("{uki_filename}.hash"));
        } else {
            // ==========================================
            // パターン B: Raw カーネル (atomic_copy_if_changed)
            // ==========================================
            let vmlinuz_filename = format!("neet-gen-{gen_num}-vmlinuz");
            let dest_kernel = kernels_dir.join(&vmlinuz_filename);
            if atomic::atomic_copy_if_changed(Path::new(&spec.kernel), &dest_kernel, 0o755)? {
                println!("esp-sync: installed {}", dest_kernel.display());
            }
            keep_kernel_files.insert(vmlinuz_filename);

            if let Some(ref initrd_src) = spec.initrd {
                let initrd_filename = format!("neet-gen-{gen_num}-initrd");
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

/// UKI 専用のインストール（署名とハッシュキャッシュ対応）
fn install_uki_if_changed(
    src: &Path,
    dest: &Path,
    key: Option<&Path>,
    cert: Option<&Path>,
) -> io::Result<()> {
    if !src.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("source UKI not found: {}", src.display()),
        ));
    }

    let hash_file = dest.with_file_name(format!(
        "{}.hash",
        dest.file_name().unwrap_or_default().to_string_lossy()
    ));

    // neet_core::atomic::sha256_file を直接利用！
    let src_hash = atomic::sha256_file(src)?;
    let src_hash_hex = hex_encode(&src_hash);

    // 既に同じハッシュが記録されていればスキップ
    if dest.exists() && hash_file.exists() {
        if let Ok(cached_hash) = fs::read_to_string(&hash_file) {
            if cached_hash.trim() == src_hash_hex {
                return Ok(()); // 既に最新
            }
        }
    }

    // 鍵と証明書が揃っていれば署名
    if let (Some(k), Some(c)) = (key, cert) {
        println!(
            "esp-sync: signing and installing UKI to {} (cert: {})",
            dest.display(),
            c.display()
        );
        let status = Command::new("sbsign")
            .arg("--key")
            .arg(k)
            .arg("--cert")
            .arg(c)
            .arg("--output")
            .arg(dest)
            .arg(src)
            .status()
            .map_err(|e| {
                io::Error::new(
                    io::ErrorKind::Other,
                    format!("failed to execute sbsign: {e}. Is 'sbsigntool' installed?"),
                )
            })?;

        if !status.success() {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("sbsign failed for {}", src.display()),
            ));
        }
    } else {
        println!("esp-sync: installing un-signed UKI to {}", dest.display());
        atomic::atomic_copy_if_changed(src, dest, 0o755)?;
    }

    let _ = fs::write(&hash_file, src_hash_hex);
    Ok(())
}

fn hex_encode(bytes: &[u8; 32]) -> String {
    let mut s = String::with_capacity(64);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{:02x}", b);
    }
    s
}
