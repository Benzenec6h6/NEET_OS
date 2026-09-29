//! efistub-install
//!
//! Bootspec-aware UEFI Direct Boot (EFISTUB) manager for NEET OS.

use bootspec::Document;
use std::collections::HashSet;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!("usage: efistub-install <boot-dir> <disk-device> <part-num>");
        eprintln!("example: efistub-install /boot /dev/nvme0n1 1");
        std::process::exit(1);
    }

    let boot_dir = Path::new(&args[1]);
    let disk_dev = &args[2];
    let part_num = &args[3];

    println!("efistub-install: target ESP = {}", boot_dir.display());

    // 1. ディレクトリ準備 (/boot/EFI/NEET)
    let efi_neet_dir = boot_dir.join("EFI/NEET");
    fs::create_dir_all(&efi_neet_dir)?;

    // 2. 世代の取得
    let generations = get_generations()?;
    if generations.is_empty() {
        eprintln!("efistub-install: no generations found");
        return Ok(());
    }

    // 3. 現在登録されている NEET OS の NVRAM エントリ一覧を取得
    let existing_entries = get_current_nvram_entries()?;

    let mut keep_files = HashSet::new();
    let mut keep_gen_numbers = HashSet::new();

    // 最新世代から順に処理 (降順)
    for gen in &generations {
        let gen_num = gen.number;
        keep_gen_numbers.insert(gen_num);

        let boot_json_path = gen.path.join("boot.json");
        let json_text = fs::read_to_string(&boot_json_path)?;
        let doc: Document = serde_json::from_str(&json_text)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

        let spec = &doc.bootspec;

        let kernel_name = format!("gen-{gen_num}-vmlinuz.efi");
        let initrd_name = format!("gen-{gen_num}-initrd.img");

        let dest_kernel = efi_neet_dir.join(&kernel_name);
        let dest_initrd = efi_neet_dir.join(&initrd_name);

        // カーネルと initrd を ESP にコピー
        install_file_if_changed(Path::new(&spec.kernel), &dest_kernel)?;
        if let Some(ref initrd_src) = spec.initrd {
            install_file_if_changed(Path::new(initrd_src), &dest_initrd)?;
        }

        keep_files.insert(kernel_name.clone());
        keep_files.insert(initrd_name.clone());

        // 4. efibootmgr 用のパラメータ構築
        // UEFI パスはバックスラッシュ区切り (例: \EFI\NEET\...)
        let uefi_loader_path = format!(r"\EFI\NEET\{kernel_name}");
        let uefi_initrd_path = format!(r"\EFI\NEET\{initrd_name}");

        let label = format!("NEET OS (Generation {gen_num})");
        let cmdline = format!(
            "initrd={} init={} {}",
            uefi_initrd_path,
            spec.init,
            spec.kernel_params.join(" ")
        );

        // 既にこの世代の NVRAM エントリが存在するか確認
        if let Some(boot_num) = existing_entries.get(&label) {
            println!("efistub-install: Entry '{label}' already exists as Boot{boot_num}");
        } else {
            println!("efistub-install: Creating NVRAM entry for '{label}'...");
            let status = Command::new("efibootmgr")
                .args([
                    "--create",
                    "--disk",
                    disk_dev,
                    "--part",
                    part_num,
                    "--label",
                    &label,
                    "--loader",
                    &uefi_loader_path,
                    "-u",
                    &cmdline,
                ])
                .status()?;
            if !status.success() {
                eprintln!("efistub-install: warning: failed to create boot entry via efibootmgr");
            }
        }
    }

    // 5. 不要になった古い世代の NVRAM エントリを削除 (GC)
    for (label, boot_num) in existing_entries {
        if let Some(gen_num) = parse_gen_from_label(&label) {
            if !keep_gen_numbers.contains(&gen_num) {
                println!("efistub-install: Removing obsolete NVRAM entry Boot{boot_num} ({label})");
                let _ = Command::new("efibootmgr")
                    .args(["-b", &boot_num, "-B"])
                    .status();
            }
        }
    }

    // 6. 不要になった ESP 内のカーネルファイルを掃除
    cleanup_unused_files(&efi_neet_dir, &keep_files)?;

    println!("efistub-install: EFISTUB generation sync completed successfully!");
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

/// efibootmgr をパースして既存の "NEET OS (Generation X)" エントリを抽出
fn get_current_nvram_entries() -> io::Result<std::collections::HashMap<String, String>> {
    let mut map = std::collections::HashMap::new();
    let output = Command::new("efibootmgr").output()?;
    let stdout = String::from_utf8_lossy(&output.stdout);

    for line in stdout.lines() {
        // 例: "Boot0001* NEET OS (Generation 2)	HD(1,GPT,...)"
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

fn install_file_if_changed(src: &Path, dest: &Path) -> io::Result<()> {
    if !dest.exists() {
        println!("efistub-install: copying {}", dest.display());
        fs::copy(src, dest)?;
        return Ok(());
    }
    if fs::metadata(src)?.len() != fs::metadata(dest)?.len() {
        println!("efistub-install: updating {}", dest.display());
        fs::copy(src, dest)?;
    }
    Ok(())
}

fn cleanup_unused_files(dir: &Path, keep_files: &HashSet<String>) -> io::Result<()> {
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !keep_files.contains(&name) {
            println!("efistub-install: removing old file {}", name);
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(())
}
