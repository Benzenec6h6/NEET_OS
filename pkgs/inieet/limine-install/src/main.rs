//! limine-install
//!
//! UEFI bootloader installer for NEET OS (Limine).
//! Installs BOOTX64.EFI and generates /boot/limine.conf.
//! Payload synchronization is delegated to esp-sync.

use bootspec::Document;
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

fn main() -> io::Result<()> {
    let args: Vec<String> = env::args().collect();
    if args.len() < 3 {
        eprintln!("usage: limine-install <boot-dir> <limine-pkg-path>");
        eprintln!("example: limine-install /boot /nix/store/...-limine");
        std::process::exit(1);
    }

    let boot_dir = Path::new(&args[1]);
    let limine_pkg = Path::new(&args[2]);

    println!("limine-install: target boot dir = {}", boot_dir.display());

    // 1. Limine UEFI バイナリ (BOOTX64.EFI) を配置
    let efi_boot_dir = boot_dir.join("EFI/BOOT");
    fs::create_dir_all(&efi_boot_dir)?;

    let src_efi = limine_pkg.join("share/limine/BOOTX64.EFI");
    let dest_efi = efi_boot_dir.join("BOOTX64.EFI");
    install_file_if_changed(&src_efi, &dest_efi)?;

    // 2. プロファイルから全世代を取得
    let generations = get_generations()?;
    if generations.is_empty() {
        eprintln!("limine-install: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    // 3. limine.conf の構築
    let timeout: u32 = env::var("LIMINE_TIMEOUT")
        .ok()
        .and_then(|t| t.parse().ok())
        .unwrap_or(5);

    let mut limine_conf = String::new();
    limine_conf.push_str(&format!("timeout: {}\n\n", timeout));

    for (idx, gen) in generations.iter().enumerate() {
        let is_latest = idx == 0;
        let gen_num = gen.number;
        let boot_json_path = gen.path.join("boot.json");

        if !boot_json_path.exists() {
            continue;
        }

        let json_str = fs::read_to_string(&boot_json_path)?;
        let doc: Document = serde_json::from_str(&json_str)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        let spec = doc.bootspec;

        let title = if is_latest {
            format!("/NEET OS (Generation {gen_num} - Current)")
        } else {
            format!("/NEET OS (Generation {gen_num})")
        };

        if spec.uki.is_some() {
            // --- パターン A: UKI (efi_chainload) ---
            let uki_path = format!("boot():/EFI/Linux/neet-gen-{gen_num}.efi");

            limine_conf.push_str(&format!("{title}\n"));
            limine_conf.push_str("    protocol: efi_chainload\n");
            limine_conf.push_str(&format!("    image_path: {uki_path}\n\n"));
        } else {
            // --- パターン B: Raw カーネル (protocol: linux) ---
            let kernel_path = format!("boot():/kernels/neet-gen-{gen_num}-vmlinuz");
            let cmdline = format!("init={} {}", spec.init, spec.kernel_params.join(" "));

            limine_conf.push_str(&format!("{title}\n"));
            limine_conf.push_str("    protocol: linux\n");
            limine_conf.push_str(&format!("    kernel_path: {kernel_path}\n"));

            if spec.initrd.is_some() {
                let initrd_path = format!("boot():/kernels/neet-gen-{gen_num}-initrd");
                limine_conf.push_str(&format!("    module_path: {initrd_path}\n"));
            }

            limine_conf.push_str(&format!("    cmdline: {cmdline}\n\n"));
        }
    }

    // 4. limine.conf をアトミックに書き込み
    let conf_path = boot_dir.join("limine.conf");
    let conf_tmp = boot_dir.join("limine.conf.tmp");
    fs::write(&conf_tmp, limine_conf)?;
    fs::rename(conf_tmp, conf_path)?;

    println!("limine-install: /boot/limine.conf updated successfully");
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

fn install_file_if_changed(src: &Path, dest: &Path) -> io::Result<()> {
    if !dest.exists() {
        println!("limine-install: installing {}", dest.display());
        fs::copy(src, dest)?;
        return Ok(());
    }

    let src_meta = fs::metadata(src)?;
    let dest_meta = fs::metadata(dest)?;

    if src_meta.len() != dest_meta.len() {
        println!("limine-install: updating {}", dest.display());
        fs::copy(src, dest)?;
    }
    Ok(())
}
