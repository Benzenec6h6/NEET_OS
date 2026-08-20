use nix::mount::{mount, MsFlags};
use nix::sys::stat::{mknod, Mode, SFlag};
use std::fs;
use std::io;
use std::path::Path;

/// 必須ファイルシステムのマウント準備
pub fn setup_essential_fs() -> io::Result<()> {
    let mounts = [
        ("proc", "/proc", "proc"),
        ("sysfs", "/sys", "sysfs"),
        ("devtmpfs", "/dev", "devtmpfs"),
        ("tmpfs", "/run", "tmpfs"),
        ("tmpfs", "/tmp", "tmpfs"),
    ];

    for (source, target, fstype) in mounts {
        fs::create_dir_all(target)?;

        println!("system-init: mounting {} on {}", fstype, target);
        if let Err(e) = mount(
            Some(source),
            target,
            Some(fstype),
            MsFlags::empty(),
            None::<&str>,
        ) {
            if e != nix::errno::Errno::EBUSY {
                eprintln!("system-init: warning: failed to mount {}: {}", target, e);
            }
        }
    }

    let net_dir = Path::new("/dev/net");
    if !net_dir.exists() {
        let _ = fs::create_dir_all(net_dir);
    }
    let tun_path = net_dir.join("tun");
    if !tun_path.exists() {
        // char device, major 10, minor 200
        let dev = nix::sys::stat::makedev(10, 200);
        let _ = mknod(
            &tun_path,
            SFlag::S_IFCHR,
            Mode::from_bits_truncate(0o666),
            dev,
        );
    }

    fs::create_dir_all("/var/log")?;
    Ok(())
}
