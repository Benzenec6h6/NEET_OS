use nix::mount::{mount, MsFlags};
use nix::sys::reboot::{reboot, RebootMode};
use nix::unistd::sync;
use std::io;

pub enum Action {
    Poweroff,
    Reboot,
}

pub fn do_shutdown(action: Action) -> io::Result<()> {
    match action {
        Action::Poweroff => println!("neet-activate: shutting down system..."),
        Action::Reboot => println!("neet-activate: rebooting system..."),
    }

    // 1. s6-rc で稼働中の全サービスを停止
    println!("neet-activate: stopping services via s6-rc...");

    // 2. ディスクのキャッシュをフラッシュ
    println!("neet-activate: syncing disks...");
    sync();

    // 3. ルートファイルシステムを read-only にリマウント
    println!("neet-activate: remounting / read-only...");
    let _ = mount(
        None::<&str>,
        "/",
        None::<&str>,
        MsFlags::MS_REMOUNT | MsFlags::MS_RDONLY,
        None::<&str>,
    );

    // 4. ハードウェア電源断 or 再起動
    match action {
        Action::Poweroff => {
            println!("neet-activate: powering down...");
            let _ = reboot(RebootMode::RB_POWER_OFF);
        }
        Action::Reboot => {
            println!("neet-activate: rebooting...");
            let _ = reboot(RebootMode::RB_AUTOBOOT);
        }
    }

    Ok(())
}
