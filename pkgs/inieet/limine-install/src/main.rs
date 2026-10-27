//! limine-install
//!
//! UEFI bootloader installer for NEET OS (Limine).
//! - Installs and optionally signs BOOTX64.EFI with hash caching
//! - Generates /boot/limine.conf atomically
//! - Idempotently registers Limine into UEFI NVRAM via neet_core::uefi

use neet_core::{generation, uefi};
use std::env;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

const LIMINE_NVRAM_LABEL: &str = "Limine Bootloader";

struct Opts {
    boot_dir: PathBuf,
    limine_pkg: PathBuf,
    key: Option<PathBuf>,
    cert: Option<PathBuf>,
    timeout: u32,
}

fn err(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

fn parse_args() -> Result<Opts, String> {
    let mut args = env::args().skip(1);
    let mut boot_dir = None;
    let mut limine_pkg = None;
    let mut key = None;
    let mut cert = None;
    let mut timeout = 5;

    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--key" => {
                key = Some(PathBuf::from(args.next().ok_or("missing value for --key")?));
            }
            "--cert" => {
                cert = Some(PathBuf::from(
                    args.next().ok_or("missing value for --cert")?,
                ));
            }
            "--timeout" => {
                let val = args.next().ok_or("missing value for --timeout")?;
                timeout = val
                    .parse::<u32>()
                    .map_err(|e| format!("invalid value for --timeout: {e}"))?;
            }
            s if !s.starts_with('-') => {
                if boot_dir.is_none() {
                    boot_dir = Some(PathBuf::from(s));
                } else if limine_pkg.is_none() {
                    limine_pkg = Some(PathBuf::from(s));
                } else {
                    return Err(format!("unexpected positional argument '{s}'"));
                }
            }
            _ => return Err(format!("unexpected argument '{arg}'")),
        }
    }

    let boot_dir = boot_dir
        .ok_or("usage: limine-install [--key <key>] [--cert <cert>] <boot-dir> <limine-pkg>")?;
    let limine_pkg = limine_pkg
        .ok_or("usage: limine-install [--key <key>] [--cert <cert>] <boot-dir> <limine-pkg>")?;

    Ok(Opts {
        boot_dir,
        limine_pkg,
        key,
        cert,
        timeout,
    })
}

fn main() -> io::Result<()> {
    let opts = parse_args().map_err(err)?;

    if !opts.boot_dir.exists() {
        return Err(err(format!(
            "boot directory does not exist: {}",
            opts.boot_dir.display()
        )));
    }

    println!(
        "limine-install: target boot dir = {}",
        opts.boot_dir.display()
    );

    // 1. Limine UEFI バイナリ (BOOTX64.EFI) を配置＆署名
    let efi_boot_dir = opts.boot_dir.join("EFI/BOOT");
    let src_efi = opts.limine_pkg.join("share/limine/BOOTX64.EFI");
    let dest_efi = efi_boot_dir.join("BOOTX64.EFI");

    neet_core::secureboot::install_and_sign_efi_cached(
        &src_efi,
        &dest_efi,
        opts.key.as_deref(),
        opts.cert.as_deref(),
        Some("limine-install"),
    )?;

    // 2. プロファイルから世代を取得し limine.conf を生成 (neet-core)
    let (generations, _skipped) = generation::list(Path::new(generation::PROFILES))?;
    if generations.is_empty() {
        eprintln!("limine-install: no generations found in /nix/var/nix/profiles");
        return Ok(());
    }

    generate_limine_conf(&opts.boot_dir, &generations, opts.timeout)?;

    // 3. UEFI NVRAM へ Limine を登録 (未登録時のみ / neet-core::uefi 利用)
    register_nvram_if_needed(&opts.boot_dir)?;

    println!("limine-install: Limine setup completed successfully");
    Ok(())
}

/// limine.conf のアトミック生成
fn generate_limine_conf(
    boot_dir: &Path,
    generations: &[generation::Generation],
    timeout: u32,
) -> io::Result<()> {
    let mut conf = String::new();
    conf.push_str(&format!("timeout: {}\n\n", timeout));

    for (idx, gen) in generations.iter().enumerate() {
        let Some(spec) = gen.bootspec()? else {
            continue;
        };

        let is_latest = idx == 0;
        let title = if is_latest {
            format!("/NEET OS (Generation {} - Current)", gen.number)
        } else {
            format!("/NEET OS (Generation {})", gen.number)
        };

        if spec.uki.is_some() {
            let uki_path = format!("boot():/EFI/Linux/{}", gen.uki_name());
            conf.push_str(&format!("{title}\n"));
            conf.push_str("    protocol: efi_chainload\n");
            conf.push_str(&format!("    image_path: {uki_path}\n\n"));
        } else {
            let kernel_path = format!("boot():/kernels/{}", gen.kernel_name());
            let cmdline = format!("init={} {}", spec.init, spec.kernel_params.join(" "));

            conf.push_str(&format!("{title}\n"));
            conf.push_str("    protocol: linux\n");
            conf.push_str(&format!("    kernel_path: {kernel_path}\n"));

            if spec.initrd.is_some() {
                let initrd_path = format!("boot():/kernels/{}", gen.initrd_name());
                conf.push_str(&format!("    module_path: {initrd_path}\n"));
            }

            conf.push_str(&format!("    cmdline: {cmdline}\n\n"));
        }
    }

    let conf_path = boot_dir.join("limine.conf");
    let conf_tmp = boot_dir.join("limine.conf.tmp");
    fs::write(&conf_tmp, conf)?;
    fs::rename(conf_tmp, conf_path)?;

    println!("limine-install: /boot/limine.conf updated successfully");
    Ok(())
}

/// neet_core::uefi を使って安全に NVRAM を登録
fn register_nvram_if_needed(boot_dir: &Path) -> io::Result<()> {
    if !uefi::is_efivarfs_mounted() {
        println!("limine-install: efivars not mounted, skipping NVRAM registration");
        return Ok(());
    }

    // 既にエントリがあればスキップ
    if uefi::has_boot_entry(LIMINE_NVRAM_LABEL) {
        println!("limine-install: NVRAM entry '{LIMINE_NVRAM_LABEL}' already exists, skipping");
        return Ok(());
    }

    // ESP を自動検出して登録
    let esp = uefi::detect_esp(boot_dir)?;
    println!(
        "limine-install: creating NVRAM entry on {} (part {})...",
        esp.disk, esp.partition
    );

    uefi::create_boot_entry(
        &esp.disk,
        &esp.partition,
        LIMINE_NVRAM_LABEL,
        r"\EFI\BOOT\BOOTX64.EFI",
        None,
    )?;

    Ok(())
}
