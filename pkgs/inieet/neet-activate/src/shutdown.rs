use nix::mount::{mount, MsFlags};
use nix::sys::reboot::{reboot, RebootMode};
use nix::sys::signal::{kill, sigaction, SaFlags, SigAction, SigHandler, SigSet, Signal};
use nix::unistd::{sync, Pid};
use std::io;
use std::process::Command;
use std::thread::sleep;
use std::time::Duration;

pub enum Action {
    Poweroff,
    Reboot,
}

pub fn do_shutdown(action: Action) -> io::Result<()> {
    match action {
        Action::Poweroff => println!("neet-activate: shutting down system..."),
        Action::Reboot => println!("neet-activate: rebooting system..."),
    }

    // 0. 自分自身が SIGTERM で死なないように無視を設定 (nix のみで完結)
    unsafe {
        let sa = SigAction::new(SigHandler::SigIgn, SaFlags::empty(), SigSet::empty());
        let _ = sigaction(Signal::SIGTERM, &sa);
    }

    // 1. 全ユーザープロセスに SIGTERM を送信
    // Pid::from_raw(-1) で自身と init 以外の全プロセスへ一斉送信
    // これにより user-session.sh の trap cleanup EXIT が起動します
    println!("neet-activate: sending SIGTERM to all processes...");
    let _ = kill(Pid::from_raw(-1), Signal::SIGTERM);

    // 2. ユーザーセッション(user-session.sh)の cleanup が完了するのを少し待機
    sleep(Duration::from_millis(1500));

    // 3. 終了しなかったプロセスに SIGKILL を送信
    println!("neet-activate: sending SIGKILL to remaining processes...");
    let _ = kill(Pid::from_raw(-1), Signal::SIGKILL);
    sleep(Duration::from_millis(500));

    // 4. システム側の s6-rc サービスを正常停止
    println!("neet-activate: stopping system services via s6-rc...");
    let _ = Command::new("s6-rc")
        .args(&["-l", "/run/service", "-da", "change"])
        .status();

    // 5. ディスクキャッシュをフラッシュ
    println!("neet-activate: syncing disks...");
    sync();

    // 6. ルートファイルシステムを read-only にリマウント
    println!("neet-activate: remounting / read-only...");
    let _ = mount(
        None::<&str>,
        "/",
        None::<&str>,
        MsFlags::MS_REMOUNT | MsFlags::MS_RDONLY,
        None::<&str>,
    );

    // 7. 電源断 or 再起動
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
