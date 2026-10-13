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

use neet_core::atomic::atomic_symlink;
use neet_core::manifest::Core;
use std::env;
use std::io;
use std::path::Path;

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
            let Some(core_arg) = args.get(2) else {
                eprintln!("usage: system-init switch <core>");
                std::process::exit(1);
            };
            let result = Core::load(Path::new(core_arg)).and_then(|c| run_switch(&c));
            if let Err(e) = result {
                eprintln!("system-init: switch failed: {e}");
                std::process::exit(1);
            }
        }

        // それ以外（通常ブート時）
        _ => {
            let Some(core_arg) = args.get(1) else {
                eprintln!("usage: system-init <core>\n   or: system-init switch <core>");
                std::process::exit(1);
            };
            let result = Core::load(Path::new(core_arg)).and_then(|c| run(&c));
            if let Err(e) = result {
                eprintln!("system-init: fatal: {e}");
                std::process::exit(1);
            }
        }
    }
}

/// 稼働中の動的切り替え（rebuild switch 用）
fn run_switch(core: &Core) -> io::Result<()> {
    core.validate()?;
    println!("system-init: [switch] updating system configuration...");

    // 1. 新しい世代の /etc を同期
    println!("system-init: [switch] syncing /etc...");
    etc_syncer::setup_etc(&core.etc(), &[])?;

    // 2. /run/current-system を新しい core に張り替える
    atomic_symlink(&core.path, Path::new("/run/current-system"))?;

    // 3. 基本ディレクトリと互換リンクの整合性を維持
    fs_setup::setup_base_directories()?;

    // 4. 新しい wrappers.json に基づいてラッパーバイナリを再生成
    if let Err(e) = wrappers::setup_wrappers() {
        eprintln!("system-init: [switch] warning: failed to setup wrappers: {e}");
    }

    // 5. /bin 配下のリンクを新しい世代に更新
    bin_setup::setup_bin(&core.system_path())?;

    // 6. 新規追加されたユーザーがいればホームディレクトリ等を準備
    let users = etc_syncer::user_group::parse_passwd().unwrap_or_default();
    fs_setup::setup_user_directories(&users)?;

    println!("system-init: [switch] core system updated successfully.");
    Ok(())
}

/// 起動時初期化
fn run(core: &Core) -> io::Result<()> {
    core.validate()?;

    // 1. /etc の同期を最優先
    etc_syncer::setup_etc(&core.etc(), &[])?;

    // 2. 次にマウントを実行 (/run や /tmp を準備する)
    let plan_path = Path::new("/etc/mount-plan.json");
    fs_setup::setup_filesystems(plan_path)?;

    // /run がマウントされた直後に世代リンクを作る
    atomic_symlink(&core.path, Path::new("/run/current-system"))?;
    atomic_symlink(&core.path, Path::new("/run/booted-system"))?;

    // /var や /run 関連の基本ディレクトリ・互換リンクを整える
    fs_setup::setup_base_directories()?;

    // 3. Wrapper を作成
    if let Err(e) = wrappers::setup_wrappers() {
        eprintln!("system-init: warning: failed to setup wrappers: {e}");
    }

    // 4. その他の初期化
    modules_setup::setup_kernel_modules(&core.modules())?;
    let _ = modules_setup::load_configured_modules();
    firmware_setup::setup_firmware(&core.firmware())?;
    net_setup::setup_existing_network()?;
    bin_setup::setup_bin(&core.system_path())?;

    let users = etc_syncer::user_group::parse_passwd().unwrap_or_default();
    fs_setup::setup_user_directories(&users)?;

    Ok(())
}
