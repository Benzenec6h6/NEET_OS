//! system-init
//!
//! System initialization binary for Nix-based environments.

mod bin_setup;
mod etc_syncer;
mod fs_setup;
mod modules_setup;
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
    fs_setup::setup_essential_fs()?;
    modules_setup::setup_kernel_modules(kernel_path)?;
    bin_setup::setup_bin(system_path)?;
    etc_syncer::setup_etc(store_etc, prune)?;
    s6_setup::setup_s6_services()?;

    Ok(())
}
