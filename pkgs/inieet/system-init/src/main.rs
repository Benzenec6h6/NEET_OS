//! system-init
//!
//! System initialization binary for Nix-based environments.

mod bin_setup;
mod etc_syncer;
mod firmware_setup;
mod fs_setup;
mod modules_setup;
mod net_setup;
mod shutdown;
mod wrappers;

use std::env;
use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};

fn main() {
    let args: Vec<String> = env::args().collect();

    // 実行されたバイナリの名前（/bin/poweroff なら "poweroff"）を取得
    let prog_name = Path::new(&args[0])
        .file_name()
        .and_then(|n| n.to_str())
        .unwrap_or("");

    // 1. "poweroff" や "reboot" という名前で直接叩かれた場合の分岐
    match prog_name {
        "poweroff" => {
            let _ = shutdown::do_shutdown(shutdown::Action::Poweroff);
            std::process::exit(0);
        }
        "reboot" => {
            let _ = shutdown::do_shutdown(shutdown::Action::Reboot);
            std::process::exit(0);
        }
        _ => {}
    }

    let subcommand = args.get(1).map(|s| s.as_str());
    match subcommand {
        Some("poweroff") => {
            let _ = shutdown::do_shutdown(shutdown::Action::Poweroff);
        }
        Some("reboot") => {
            let _ = shutdown::do_shutdown(shutdown::Action::Reboot);
        }
        Some("switch") => {
            if args.len() < 4 {
                eprintln!(
                    "usage: system-init switch <store-etc-path> <system-path> [prune-path ...]"
                );
                std::process::exit(1);
            }

            let store_etc = PathBuf::from(&args[2]);
            let system_path = PathBuf::from(&args[3]);
            let prune: Vec<PathBuf> = args[4..].iter().map(PathBuf::from).collect();

            if let Err(e) = run_switch(&store_etc, &system_path, &prune) {
                eprintln!("system-init: switch failed: {e}");
                std::process::exit(1);
            }
        }

        // それ以外（通常ブート時）
        _ => {
            if args.len() < 5 {
                eprintln!(
                    "usage: system-init <store-etc-path> <system-path> <kernel-path> [prune-path ...]"
                );
                eprintln!(
                    "   or: system-init switch <store-etc-path> <system-path> [prune-path ...]"
                );
                std::process::exit(1);
            }

            let store_etc = PathBuf::from(&args[1]);
            let system_path = PathBuf::from(&args[2]);
            let kernel_path = PathBuf::from(&args[3]);
            let firmware_path = PathBuf::from(&args[4]);
            let prune: Vec<PathBuf> = args[5..].iter().map(PathBuf::from).collect();

            if let Err(e) = run(
                &store_etc,
                &system_path,
                &kernel_path,
                &firmware_path,
                &prune,
            ) {
                eprintln!("system-init: fatal: {e}");
                std::process::exit(1);
            }
        }
    }
}

/// 稼働中の動的切り替え（rebuild switch 用）
fn run_switch(store_etc: &Path, system_path: &Path, prune: &[PathBuf]) -> io::Result<()> {
    println!("system-init: [switch] updating system configuration...");

    // 1. 新しい世代の /etc を同期 (wrappers.json などの設定も最新になる)
    println!("system-init: [switch] syncing /etc...");
    etc_syncer::setup_etc(store_etc, prune)?;

    // 2. /run/current-system を新しい system-path に張り替える
    setup_current_system(system_path)?;

    // 3. 基本ディレクトリと互換リンクの整合性を維持
    fs_setup::setup_base_directories()?;

    // 4. 新しい wrappers.json に基づいてラッパーバイナリを再生成
    if let Err(e) = wrappers::setup_wrappers() {
        eprintln!("system-init: [switch] warning: failed to setup wrappers: {e}");
    }

    // 5. /bin 配下のリンクを新しい世代に更新
    bin_setup::setup_bin(system_path)?;

    // 6. 新規追加されたユーザーがいればホームディレクトリ等を準備
    let users = etc_syncer::user_group::parse_passwd().unwrap_or_default();
    fs_setup::setup_user_directories(&users)?;

    println!("system-init: [switch] core system updated successfully.");
    Ok(())
}

/// 起動時初期化（既存コードのまま変更なし）
fn run(
    store_etc: &Path,
    system_path: &Path,
    kernel_path: &Path,
    firmware_path: &Path,
    prune: &[PathBuf],
) -> io::Result<()> {
    // 1. /etc の同期を最優先（mount-plan.json や wrappers.json を配置するため）
    etc_syncer::setup_etc(store_etc, prune)?;

    // 2. 次にマウントを実行 (/run や /tmp を準備する)
    let plan_path = Path::new("/etc/mount-plan.json");
    fs_setup::setup_filesystems(plan_path)?;

    // /run がマウントされた直後に /run/current-system を作成
    setup_current_system(system_path)?;

    let _ = fs_setup::ensure_symlink(kernel_path, Path::new("/run/booted-kernel"));

    // /var や /run 関連の基本ディレクトリ・互換リンクを整える
    fs_setup::setup_base_directories()?;

    // 3. マウントが終わった綺麗な /run に対して Wrapper を作成する
    if let Err(e) = wrappers::setup_wrappers() {
        eprintln!("system-init: warning: failed to setup wrappers: {e}");
    }

    // 4. その他の初期化 (パスをマウント済みの / に対して行う)
    modules_setup::setup_kernel_modules(kernel_path)?;
    let _ = modules_setup::load_configured_modules();
    firmware_setup::setup_firmware(firmware_path)?;
    net_setup::setup_existing_network()?;
    bin_setup::setup_bin(system_path)?;

    let users = etc_syncer::user_group::parse_passwd().unwrap_or_default();
    fs_setup::setup_user_directories(&users)?;

    Ok(())
}

/// /run/current-system -> <system-path> のシンボリックリンクを作成する
fn setup_current_system(system_path: &Path) -> io::Result<()> {
    let link_path = Path::new("/run/current-system");

    // 既に存在している（または壊れたリンクが残っている）場合は一旦削除
    let _ = fs::remove_file(link_path);

    symlink(system_path, link_path)?;
    println!(
        "system-init: created symlink /run/current-system -> {}",
        system_path.display()
    );
    Ok(())
}
