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
    max_generations: Option<usize>,
    gc_only: bool,
}

fn parse_args() -> Result<Opts, String> {
    let mut args = env::args().skip(1);
    let mut boot_dir = None;
    let mut profiles_dir = PathBuf::from(generation::PROFILES);
    let mut key = None;
    let mut cert = None;
    let mut max_generations = None;
    let mut gc_only = false;

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
            "--max-generations" => {
                let val = args
                    .next()
                    .ok_or("esp-sync: missing value for --max-generations")?;
                let n = val
                    .parse::<usize>()
                    .map_err(|e| format!("esp-sync: invalid --max-generations '{val}': {e}"))?;
                if n == 0 {
                    return Err("esp-sync: --max-generations must be >= 1".to_string());
                }
                max_generations = Some(n);
            }
            "--gc-only" => {
                gc_only = true;
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
        "usage: esp-sync [--profiles <dir>] [--key <db.key>] [--cert <db.crt>] [--max-generations <N>] [--gc-only] <boot-dir>",
    )?;

    Ok(Opts {
        boot_dir,
        profiles_dir,
        key,
        cert,
        max_generations,
        gc_only,
    })
}

/// coreutils `df -B1 -P` で利用可能バイト数を取得（失敗時は None を返しフォールバック）
fn available_bytes(path: &Path) -> Option<u64> {
    let out = Command::new("df")
        .args(["-B1", "-P"])
        .arg(path)
        .output()
        .ok()?;
    if !out.status.success() {
        return None;
    }
    let stdout = String::from_utf8_lossy(&out.stdout);
    let line = stdout.lines().nth(1)?;
    line.split_whitespace().nth(3)?.parse::<u64>().ok()
}

/// 新規に作成が必要なファイルの概算サイズを計算する（既存キャッシュは無視）
fn estimate_missing_payload_bytes(
    generations: &[generation::Generation],
    efi_linux_dir: &Path,
    kernels_dir: &Path,
) -> io::Result<u64> {
    let mut total = 0u64;
    for gen in generations {
        let Some(spec) = gen.bootspec()? else {
            continue;
        };
        if let Some(ref uki_src) = spec.uki {
            let dest = efi_linux_dir.join(gen.uki_name());
            if !dest.exists() {
                total = total.saturating_add(fs::metadata(uki_src)?.len());
                total = total.saturating_add(64 * 1024); // 署名 + .hash 用マージン
            }
        } else {
            let dest_kernel = kernels_dir.join(gen.kernel_name());
            if !dest_kernel.exists() {
                total = total.saturating_add(fs::metadata(&spec.kernel)?.len());
            }
            if let Some(ref initrd_src) = spec.initrd {
                let dest_initrd = kernels_dir.join(gen.initrd_name());
                if !dest_initrd.exists() {
                    total = total.saturating_add(fs::metadata(initrd_src)?.len());
                }
            }
        }
    }
    Ok(total)
}

fn main() -> io::Result<()> {
    let opts = match parse_args() {
        Ok(o) => o,
        Err(msg) => {
            if msg == "help" {
                println!(
                    "usage: esp-sync [--profiles <dir>] [--key <db.key>] [--cert <db.crt>] [--max-generations <N>] [--gc-only] <boot-dir>"
                );
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

    // 2. プロファイルから世代一覧を取得（上限が指定されていれば最新 N 世代に制限）
    println!(
        "esp-sync: scanning profiles at {}",
        opts.profiles_dir.display()
    );
    let (generations, skipped) =
        generation::list_limited(&opts.profiles_dir, opts.max_generations)?;
    for (num, err) in skipped {
        eprintln!("esp-sync: warning: skipped generation {num}: {err}");
    }
    println!(
        "esp-sync: keeping {} generation(s){}",
        generations.len(),
        opts.max_generations
            .map(|n| format!(" (limit: {n})"))
            .unwrap_or_default()
    );

    if generations.is_empty() {
        eprintln!(
            "esp-sync: [WARNING] no generations found in {}",
            opts.profiles_dir.display()
        );
        eprintln!("esp-sync: [WARNING] skipping payload sync/cleanup");
        return Ok(());
    }

    // 3. 古い世代・残留一時ファイルの削除を【配置より先】に実行 (GC)
    let active_gens: HashSet<u32> = generations.iter().map(|g| g.number).collect();

    for removed in neet_core::cleanup::cleanup_stale_generation_files(&efi_linux_dir, &active_gens)?
    {
        println!("esp-sync: removed obsolete file {}", removed.display());
    }
    for removed in neet_core::cleanup::cleanup_stale_generation_files(&kernels_dir, &active_gens)? {
        println!("esp-sync: removed obsolete file {}", removed.display());
    }

    if opts.gc_only {
        println!("esp-sync: GC-only mode completed successfully");
        return Ok(());
    }

    // 4. 空き容量の事前チェック
    let needed = estimate_missing_payload_bytes(&generations, &efi_linux_dir, &kernels_dir)?;
    if needed > 0 {
        if let Some(avail) = available_bytes(&opts.boot_dir) {
            // 1 MiB の安全マージン
            let required_with_margin = needed.saturating_add(1024 * 1024);
            if avail < required_with_margin {
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!(
                        "insufficient space on ESP ({}): need ~{} MiB, available {} MiB. \
                         Reduce boot.loader.generationLimit or run 'neet-gc'.",
                        opts.boot_dir.display(),
                        required_with_margin / (1024 * 1024),
                        avail / (1024 * 1024),
                    ),
                ));
            }
        }
    }

    // 5. 各世代の boot.json を読み取り、新しい順で ESP へ配置
    let (resolved_key, resolved_cert) = neet_core::secureboot::resolve_signing_pair(
        opts.key.as_deref(),
        opts.cert.as_deref(),
        Some("esp-sync"),
    )
    .unzip();

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
                resolved_key,
                resolved_cert,
                Some("esp-sync"),
            )?;
        } else {
            let vmlinuz_filename = gen.kernel_name();
            let dest_kernel = kernels_dir.join(&vmlinuz_filename);
            if atomic::atomic_copy_if_changed(Path::new(&spec.kernel), &dest_kernel, 0o755)? {
                println!("esp-sync: installed {}", dest_kernel.display());
            }

            if let Some(ref initrd_src) = spec.initrd {
                let initrd_filename = gen.initrd_name();
                let dest_initrd = kernels_dir.join(&initrd_filename);
                if atomic::atomic_copy_if_changed(Path::new(initrd_src), &dest_initrd, 0o644)? {
                    println!("esp-sync: installed {}", dest_initrd.display());
                }
            }
        }
    }

    println!("esp-sync: payload sync completed successfully");
    Ok(())
}
