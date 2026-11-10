use nix::mount::{mount, MsFlags};
use nix::sys::reboot::{reboot, RebootMode};
use nix::sys::signal::{kill, sigaction, SaFlags, SigAction, SigHandler, SigSet, Signal};
use nix::unistd::{sync, Pid};
use std::fs::OpenOptions;
use std::io::{self, Write};
use std::process::Command;
use std::thread::sleep;
use std::time::Duration;

pub enum Action {
    Poweroff,
    Reboot,
}

/// 端末が切断されても Broken pipe でパニックを起こさない安全なコンソール出力
fn log_console(msg: &str) {
    if let Ok(mut console) = OpenOptions::new().write(true).open("/dev/console") {
        let _ = writeln!(console, "{msg}");
    } else {
        let _ = writeln!(io::stdout(), "{msg}");
    }
}

pub fn do_shutdown(action: Action) -> io::Result<()> {
    match action {
        Action::Poweroff => log_console("neet-activate: shutting down system..."),
        Action::Reboot => log_console("neet-activate: rebooting system..."),
    }

    // 0. 端末切断シグナルを無視
    unsafe {
        let sa = SigAction::new(SigHandler::SigIgn, SaFlags::empty(), SigSet::empty());
        let _ = sigaction(Signal::SIGHUP, &sa);
        let _ = sigaction(Signal::SIGTERM, &sa);
        let _ = sigaction(Signal::SIGINT, &sa);
        let _ = sigaction(Signal::SIGQUIT, &sa);
        let _ = sigaction(Signal::SIGPIPE, &sa);
    }

    // 1. まず s6-rc で管理下の全システムサービスを依存関係順に安全停止
    // (これにより display-manager や getty も順序よく停止し、user-session.sh も正常終了する)
    log_console("neet-activate: stopping all system services via s6-rc...");
    let _ = Command::new("s6-rc").args(&["-da", "change"]).status();

    // 2. s6-rc 管理外で生き残っている一般プロセスに SIGTERM を送信
    log_console("neet-activate: sending SIGTERM to remaining processes...");
    let _ = kill(Pid::from_raw(-1), Signal::SIGTERM);
    sleep(Duration::from_millis(1000));

    // 3. それでも終了しないプロセスを強制停止 (SIGKILL)
    log_console("neet-activate: sending SIGKILL to remaining processes...");
    let _ = kill(Pid::from_raw(-1), Signal::SIGKILL);
    sleep(Duration::from_millis(200));

    // 4. ディスクキャッシュをフラッシュ
    log_console("neet-activate: syncing disks...");
    sync();

    // 5. ルートファイルシステムを read-only にリマウント
    log_console("neet-activate: remounting / read-only...");
    let _ = mount(
        None::<&str>,
        "/",
        None::<&str>,
        MsFlags::MS_REMOUNT | MsFlags::MS_RDONLY,
        None::<&str>,
    );

    // 6. 電源断 or 再起動
    match action {
        Action::Poweroff => {
            log_console("neet-activate: powering down...");
            let _ = reboot(RebootMode::RB_POWER_OFF);
        }
        Action::Reboot => {
            log_console("neet-activate: rebooting...");
            let _ = reboot(RebootMode::RB_AUTOBOOT);
        }
    }

    Ok(())
}
