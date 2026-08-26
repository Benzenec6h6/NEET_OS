//! system-init
//!
//! System initialization binary for Nix-based environments.

mod bin_setup;
mod etc_syncer;
mod fs_setup;
mod modules_setup;
mod net_setup;
mod s6_setup;

use std::env;
use std::io;
use std::path::{Path, PathBuf};

fn main() {
    let args: Vec<String> = env::args().collect();
    if args.len() < 4 {
        eprintln!(
            "usage: system-init <store-etc-path> <system-path> <kernel-path> [prune-path ...]"
        );
        std::process::exit(1);
    }

    let store_etc = PathBuf::from(&args[1]);
    let system_path = PathBuf::from(&args[2]);
    let kernel_path = PathBuf::from(&args[3]);
    let prune: Vec<PathBuf> = args[4..].iter().map(PathBuf::from).collect();

    if let Err(e) = run(&store_etc, &system_path, &kernel_path, &prune) {
        eprintln!("system-init: fatal: {e}");
        std::process::exit(1);
    }
}

fn run(
    store_etc: &Path,
    system_path: &Path,
    kernel_path: &Path,
    prune: &[PathBuf],
) -> io::Result<()> {
    // 1. /etc の同期を最優先（mount-plan.json などを配置するため）
    etc_syncer::setup_etc(store_etc, prune)?;

    // 2. 配置された mount-plan.json を読み込んでマウントを実行
    let plan_path = Path::new("/etc/mount-plan.json");
    fs_setup::setup_filesystems(plan_path, true)?;

    // 3. その他の初期化
    modules_setup::setup_kernel_modules(kernel_path)?;
    net_setup::setup_existing_network()?;
    bin_setup::setup_bin(system_path)?;

    let users = etc_syncer::user_group::parse_passwd().unwrap_or_else(|e| {
        eprintln!("system-init: warning: failed to parse /etc/passwd: {}", e);
        Vec::new()
    });

    fs_setup::setup_user_directories(&users)?;
    s6_setup::setup_s6_services()?;

    Ok(())
}
