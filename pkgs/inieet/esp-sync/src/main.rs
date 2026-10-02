//! esp-sync
//!
//! Synchronizes kernel/UKI payloads between Nix profiles and the EFI System Partition (ESP),
//! and garbage-collects obsolete files.

use bootspec::Document;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 2 {
        eprintln!("usage: esp-sync <boot-dir>");
        eprintln!("example: esp-sync /boot");
        std::process::exit(1);
    }

    let boot_dir = Path::new(&args[1]);
    if !boot_dir.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("boot directory does not exist: {}", boot_dir.display()),
        ));
    }

    println!("esp-sync: syncing ESP at {}", boot_dir.display());

    // 1. 標準ディレクトリの担保
    // - EFI/Linux: UKI の標準配置ディレクトリ (BLS Type #2)
    // - kernels: Raw カーネル/initrd 配置ディレクトリ
    let efi_linux_dir = boot_dir.join("EFI/Linux");
    let kernels_dir = boot_dir.join("kernels");
    fs::create_dir_all(&efi_linux_dir)?;
    fs::create_dir_all(&kernels_dir)?;

    // 2. 現在の Nix プロファイルから世代一覧を取得
    let generations = get_generations()?;
    if generations.is_empty() {
        println!("esp-sync: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    let mut keep_uki_files = HashSet::new();
    let mut keep_kernel_files = HashSet::new();

    // 3. 各世代の boot.json を読み取り、ESP へ配置
    for gen in &generations {
        let gen_num = gen.number;
        let boot_json_path = gen.path.join("boot.json");

        if !boot_json_path.exists() {
            eprintln!(
                "esp-sync: warning: boot.json not found in {}, skipping generation {gen_num}",
                gen.path.display()
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
            // パターン A: UKI (Unified Kernel Image)
            // ==========================================
            let uki_filename = format!("neet-gen-{gen_num}.efi");
            let dest = efi_linux_dir.join(&uki_filename);

            install_file_if_changed(Path::new(uki_src), &dest)?;
            keep_uki_files.insert(uki_filename);
        } else {
            // ==========================================
            // パターン B: 従来の Raw カーネル + initrd
            // ==========================================
            let vmlinuz_filename = format!("neet-gen-{gen_num}-vmlinuz");
            let dest_kernel = kernels_dir.join(&vmlinuz_filename);
            install_file_if_changed(Path::new(&spec.kernel), &dest_kernel)?;
            keep_kernel_files.insert(vmlinuz_filename);

            if let Some(ref initrd_src) = spec.initrd {
                let initrd_filename = format!("neet-gen-{gen_num}-initrd");
                let dest_initrd = kernels_dir.join(&initrd_filename);
                install_file_if_changed(Path::new(initrd_src), &dest_initrd)?;
                keep_kernel_files.insert(initrd_filename);
            }
        }
    }

    // 4. 古い世代のファイルを安全に削除 (GC)
    // 誤削除を防ぐため、"neet-gen-" から始まるファイルのみを対象とする
    cleanup_dir(&efi_linux_dir, &keep_uki_files, "neet-gen-")?;
    cleanup_dir(&kernels_dir, &keep_kernel_files, "neet-gen-")?;

    println!("esp-sync: payload sync completed successfully");
    Ok(())
}

struct Generation {
    number: u32,
    path: PathBuf,
}

/// /nix/var/nix/profiles/system-*-link から全世代を降順で取得
fn get_generations() -> io::Result<Vec<Generation>> {
    let profiles_dir = Path::new("/nix/var/nix/profiles");
    let mut gens = Vec::new();

    if !profiles_dir.exists() {
        return Ok(gens);
    }

    for entry in fs::read_dir(profiles_dir)? {
        let entry = entry?;
        let filename = entry.file_name();
        let name = filename.to_string_lossy();

        if name.starts_with("system-") && name.ends_with("-link") {
            let num_part = &name["system-".len()..name.len() - "-link".len()];
            if let Ok(num) = num_part.parse::<u32>() {
                if let Ok(real_path) = fs::canonicalize(entry.path()) {
                    gens.push(Generation {
                        number: num,
                        path: real_path,
                    });
                }
            }
        }
    }

    gens.sort_by(|a, b| b.number.cmp(&a.number));
    Ok(gens)
}

/// サイズが異なる場合のみコピー (無駄な ESP フラッシュ書き込みを抑制)
fn install_file_if_changed(src: &Path, dest: &Path) -> io::Result<()> {
    if !src.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("source payload not found: {}", src.display()),
        ));
    }

    if dest.exists() {
        let src_len = fs::metadata(src)?.len();
        let dest_len = fs::metadata(dest)?.len();
        if src_len == dest_len {
            return Ok(()); // 既に最新
        }
    }

    println!("esp-sync: installing {}", dest.display());
    fs::copy(src, dest)?;
    Ok(())
}

/// 指定したプレフィックスを持ち、keep_files に含まれないファイルを削除
fn cleanup_dir(dir: &Path, keep_files: &HashSet<String>, prefix: &str) -> io::Result<()> {
    if !dir.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();

        // NEET OS が配置したファイルかつ、現存プロファイルにないものを消去
        if name.starts_with(prefix) && !keep_files.contains(&name) {
            println!("esp-sync: removing obsolete file {}", name);
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(())
}
