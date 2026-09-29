//! limine-install
//!
//! UEFI bootloader installer for NEET OS (Limine).

use std::collections::HashSet;
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

    // 1. ディレクトリ構成の担保 (/boot/EFI/BOOT, /boot/kernels)
    let efi_boot_dir = boot_dir.join("EFI/BOOT");
    let kernels_dir = boot_dir.join("kernels");
    fs::create_dir_all(&efi_boot_dir)?;
    fs::create_dir_all(&kernels_dir)?;

    // 2. Limine UEFI バイナリのコピー (Removable 形式: BOOTX64.EFI)
    let src_efi = limine_pkg.join("share/limine/BOOTX64.EFI");
    let dest_efi = efi_boot_dir.join("BOOTX64.EFI");
    install_file_if_changed(&src_efi, &dest_efi)?;

    // 3. /nix/var/nix/profiles から世代のリストを取得
    let generations = get_generations()?;
    if generations.is_empty() {
        eprintln!("limine-install: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    // 4. 各世代のカーネルと initrd を /boot/kernels に配置し、limine.conf を組み立てる
    let timeout: u32 = env::var("LIMINE_TIMEOUT")
        .ok()
        .and_then(|t| t.parse().ok())
        .unwrap_or(5);

    let mut limine_conf = String::new();
    limine_conf.push_str(&format!("timeout: {}\n\n", timeout));

    let mut keep_kernel_files = HashSet::new();

    for (idx, gen) in generations.iter().enumerate() {
        let is_latest = idx == 0;
        let gen_num = gen.number;
        let toplevel = &gen.path;

        // ★ boot.json を優先的に読み込む
        let boot_json_path = toplevel.join("boot.json");
        if !boot_json_path.exists() {
            eprintln!(
                "limine-install: warning: boot.json not found in {}, skipping generation {gen_num}",
                toplevel.display()
            );
            continue;
        }

        let json_str = fs::read_to_string(&boot_json_path)?;
        let doc: bootspec::Document = serde_json::from_str(&json_str)?;
        let spec = doc.bootspec;

        // bootspec から各パスを取得
        let kernel_src = Path::new(&spec.kernel);
        let initrd_src = spec.initrd.as_ref().map(Path::new);
        let init_src = Path::new(&spec.init);
        let kernel_params = spec.kernel_params.join(" ");

        // ファイル名定義
        let kernel_dest_name = format!("gen-{gen_num}-vmlinuz");
        let initrd_dest_name = format!("gen-{gen_num}-initrd");

        let kernel_dest = kernels_dir.join(&kernel_dest_name);
        let initrd_dest = kernels_dir.join(&initrd_dest_name);

        // カーネルのコピー
        install_file_if_changed(kernel_src, &kernel_dest)?;
        keep_kernel_files.insert(kernel_dest_name.clone());

        // initrd が存在する場合はコピーしてモジュールパスに登録
        let mut module_line = String::new();
        if let Some(initrd_path) = initrd_src {
            if initrd_path.exists() {
                install_file_if_changed(initrd_path, &initrd_dest)?;
                keep_kernel_files.insert(initrd_dest_name.clone());
                module_line = format!("    module_path: boot():/kernels/{initrd_dest_name}\n");
            }
        }

        let title = if is_latest {
            format!("/NEET OS (Generation {gen_num} - Current)")
        } else {
            format!("/NEET OS (Generation {gen_num})")
        };

        // Limine エントリの記述
        limine_conf.push_str(&format!("{title}\n"));
        limine_conf.push_str("    protocol: linux\n");
        limine_conf.push_str(&format!(
            "    kernel_path: boot():/kernels/{kernel_dest_name}\n"
        ));
        if !module_line.is_empty() {
            limine_conf.push_str(&module_line);
        }
        limine_conf.push_str(&format!(
            "    cmdline: init={} {}\n\n",
            init_src.display(),
            kernel_params
        ));
    }

    // 5. limine.conf をアトミックに書き込み
    let conf_path = boot_dir.join("limine.conf");
    let conf_tmp = boot_dir.join("limine.conf.tmp");
    fs::write(&conf_tmp, limine_conf)?;
    fs::rename(conf_tmp, conf_path)?;
    println!("limine-install: updated /boot/limine.conf successfully");

    // 6. 過去の使われなくなったカーネル/initrd を掃除 (GC)
    cleanup_unused_kernels(&kernels_dir, &keep_kernel_files)?;

    Ok(())
}

struct Generation {
    number: u32,
    path: PathBuf,
}

/// /nix/var/nix/profiles/system-*-link を走査して、世代番号の降順（最新順）で返す
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
                let real_path = fs::canonicalize(entry.path())?;
                gens.push(Generation {
                    number: num,
                    path: real_path,
                });
            }
        }
    }

    gens.sort_by(|a, b| b.number.cmp(&a.number));
    Ok(gens)
}

/// ファイルサイズや mtime が異なる場合のみコピー
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

/// keep_files に含まれないファイルを /boot/kernels から削除
fn cleanup_unused_kernels(kernels_dir: &Path, keep_files: &HashSet<String>) -> io::Result<()> {
    for entry in fs::read_dir(kernels_dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        if !keep_files.contains(&name) {
            println!("limine-install: removing old kernel file {}", name);
            let _ = fs::remove_file(entry.path());
        }
    }
    Ok(())
}
