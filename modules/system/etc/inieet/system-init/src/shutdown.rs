use nix::mount::{mount, MsFlags};
use nix::sys::reboot::{reboot, RebootMode};
use nix::unistd::sync;
use std::io;
use std::process::Command;

pub enum Action {
    Poweroff,
    Reboot,
}

pub fn do_shutdown(action: Action) -> io::Result<()> {
    match action {
        Action::Poweroff => println!("system-init: shutting down system..."),
        Action::Reboot => println!("system-init: rebooting system..."),
    }

    // 1. s6-rc で稼働中の全サービスを停止
    println!("system-init: stopping services via s6-rc...");
    let _ = Command::new("s6-rc").args(["-a", "-da", "change"]).status();

    // 2. ディスクのキャッシュをフラッシュ
    println!("system-init: syncing disks...");
    sync();

    // 3. ルートファイルシステムを read-only にリマウント
    println!("system-init: remounting / read-only...");
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
            println!("system-init: powering down...");
            let _ = reboot(RebootMode::RB_POWER_OFF);
        }
        Action::Reboot => {
            println!("system-init: rebooting...");
            let _ = reboot(RebootMode::RB_AUTOBOOT);
        }
    }

    Ok(())
}
