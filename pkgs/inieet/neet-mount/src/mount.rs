//! プランの適用（実際の mount(2) 呼び出し）

use crate::btrfs_reset;
use crate::plan::MountEntry;
use crate::util::fatal;
use nix::mount::{mount, MsFlags};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

/// USB 起動などを考えて長めに取る（現れ次第すぐ抜ける）
const DEVICE_WAIT: Duration = Duration::from_secs(15);

/// root: マウント先のプレフィックス。stage1 なら "/mnt"、stage2 なら "/" を渡す。
///
/// bind マウントの失敗、btrfs リセットの失敗は `Err` を返す。
/// それ以外のマウント失敗は、strict でなければ警告に留めて続行する。
pub fn apply_plan(entries: &[MountEntry], root: &Path, strict: bool) -> io::Result<()> {
    for entry in entries {
        if entry.already_mounted {
            println!("neet-mount: skipping already mounted {}", entry.mount_point);
            continue;
        }

        let target = if entry.outside_root {
            PathBuf::from(&entry.mount_point)
        } else {
            join_root(root, &entry.mount_point)
        };
        let (flags, data_options) = parse_mount_options(&entry.options);
        let is_bind = flags.contains(MsFlags::MS_BIND);

        // bind のソースは root 配下のパス、それ以外は UUID= 等を解決したデバイスパス
        let mut source = if is_bind {
            join_root(root, &entry.device)
        } else {
            resolve_device_path(&entry.device)
        };

        wait_device(entry, &source);

        if entry.options.iter().any(|o| o == "loop") {
            let ro = entry.options.iter().any(|o| o == "ro");
            source = attach_loop(&source, ro).map_err(|e| {
                fatal(format!(
                    "failed to attach loop device for {}: {e}",
                    entry.device
                ))
            })?;
        }

        if entry.fs_type == "overlay" {
            prepare_overlay_dirs(&data_options)?;
        }

        // bind のソースが無いと mount が失敗するので事前に作る
        if is_bind && !source.exists() {
            println!(
                "neet-mount: creating bind source directory {}",
                source.display()
            );
            fs::create_dir_all(&source).map_err(|e| {
                fatal(format!(
                    "failed to create bind source {}: {e}",
                    source.display()
                ))
            })?;
        }

        // btrfs: マウント直前に旧ルートを退避してサブボリュームを作り直す
        if entry.reset_on_boot {
            if entry.fs_type == "btrfs" {
                println!(
                    "neet-mount: resetting btrfs subvolume for {} (keep {} old roots)",
                    entry.mount_point, entry.keep_old_roots
                );
                btrfs_reset::reset_subvolume(&source, &entry.options, entry.keep_old_roots)
                    .map_err(|e| {
                        fatal(format!(
                            "FATAL: failed to reset btrfs subvolume for {}: {e}",
                            entry.mount_point
                        ))
                    })?;
            } else {
                eprintln!(
                    "neet-mount: warning: resetOnBoot is only supported for btrfs (ignored for {} on {})",
                    entry.fs_type, entry.mount_point
                );
            }
        }

        println!(
            "neet-mount: mounting {} ({}) on {} ({})",
            entry.device,
            source.display(),
            target.display(),
            entry.fs_type
        );

        if let Err(e) = fs::create_dir_all(&target) {
            let msg = format!("failed to create {}: {e}", target.display());
            if is_bind || strict {
                return Err(fatal(msg));
            }
            eprintln!("neet-mount: warning: {msg}");
            continue;
        }

        let data_str = (!data_options.is_empty()).then(|| data_options.join(","));
        // bind では fstype はカーネルに無視されるので渡さない
        let fstype: Option<&str> = (!is_bind).then_some(entry.fs_type.as_str());

        match mount(Some(&source), &target, fstype, flags, data_str.as_deref()) {
            Ok(()) | Err(nix::errno::Errno::EBUSY) => {}
            Err(e) => {
                let msg = format!(
                    "failed to mount {} ({}): {e}",
                    target.display(),
                    entry.device
                );
                if is_bind || strict {
                    return Err(fatal(msg));
                }
                eprintln!("neet-mount: warning: {msg}");
            }
        }
    }
    Ok(())
}

/// デバイスの出現を待機し、現れなかった場合は警告を出力する
fn wait_device(entry: &MountEntry, dev_path: &Path) {
    if entry.is_physical_device() && !wait_for_device(dev_path, DEVICE_WAIT) {
        eprintln!(
            "neet-mount: warning: device path {} ({}) did not appear in time",
            dev_path.display(),
            entry.device
        );
    }
}

/// 指定されたデバイスノードが出現するまで待機する
fn wait_for_device(dev_path: &Path, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if dev_path.exists() {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    dev_path.exists()
}

/// UUID= や LABEL= 表記を /dev/disk/by-* の実際のパス構造に変換
fn resolve_device_path(device: &str) -> PathBuf {
    if let Some(uuid) = device.strip_prefix("UUID=") {
        PathBuf::from("/dev/disk/by-uuid").join(uuid)
    } else if let Some(partuuid) = device.strip_prefix("PARTUUID=") {
        PathBuf::from("/dev/disk/by-partuuid").join(partuuid)
    } else if let Some(label) = device.strip_prefix("LABEL=") {
        PathBuf::from("/dev/disk/by-label").join(label)
    } else if let Some(partlabel) = device.strip_prefix("PARTLABEL=") {
        PathBuf::from("/dev/disk/by-partlabel").join(partlabel)
    } else {
        PathBuf::from(device)
    }
}

/// losetup -f --show [-r] <file> でループデバイスを用意し、そのパスを返す
fn attach_loop(file: &Path, readonly: bool) -> io::Result<PathBuf> {
    let mut cmd = Command::new("losetup");
    cmd.args(["-f", "--show"]);
    if readonly {
        cmd.arg("-r");
    }
    cmd.arg(file);
    let out = cmd.output()?;
    let dev = String::from_utf8_lossy(&out.stdout).trim().to_string();
    if !out.status.success() || dev.is_empty() {
        return Err(fatal(format!(
            "{cmd:?} failed: {}",
            String::from_utf8_lossy(&out.stderr).trim()
        )));
    }
    Ok(PathBuf::from(dev))
}

/// overlay の upperdir / workdir は存在しないと mount が失敗するので作る（絶対パス前提）
fn prepare_overlay_dirs(data: &[&str]) -> io::Result<()> {
    for opt in data {
        for key in ["upperdir=", "workdir="] {
            if let Some(p) = opt.strip_prefix(key) {
                fs::create_dir_all(p)
                    .map_err(|e| fatal(format!("failed to create overlay dir {p}: {e}")))?;
            }
        }
    }
    Ok(())
}

fn join_root(root: &Path, mount_point: &str) -> PathBuf {
    let trimmed = mount_point.trim_start_matches('/');
    if trimmed.is_empty() {
        root.to_path_buf()
    } else {
        root.join(trimmed)
    }
}

fn parse_mount_options(options: &[String]) -> (MsFlags, Vec<&str>) {
    let mut flags = MsFlags::empty();
    let mut data_options = Vec::new();
    for opt in options {
        match opt.as_str() {
            "defaults" => (),
            // loop はカーネルのオプションではなく、apply_plan 側で losetup する合図
            "loop" => (),
            "ro" => flags |= MsFlags::MS_RDONLY,
            "rw" => flags &= !MsFlags::MS_RDONLY,
            "nosuid" => flags |= MsFlags::MS_NOSUID,
            "suid" => flags &= !MsFlags::MS_NOSUID,
            "nodev" => flags |= MsFlags::MS_NODEV,
            "dev" => flags &= !MsFlags::MS_NODEV,
            "noexec" => flags |= MsFlags::MS_NOEXEC,
            "exec" => flags &= !MsFlags::MS_NOEXEC,
            "sync" => flags |= MsFlags::MS_SYNCHRONOUS,
            "async" => flags &= !MsFlags::MS_SYNCHRONOUS,
            "remount" => flags |= MsFlags::MS_REMOUNT,
            "bind" => flags |= MsFlags::MS_BIND,
            "dirsync" => flags |= MsFlags::MS_DIRSYNC,
            "mand" => flags |= MsFlags::MS_MANDLOCK,
            "noatime" => flags |= MsFlags::MS_NOATIME,
            "nodiratime" => flags |= MsFlags::MS_NODIRATIME,
            "relatime" => flags |= MsFlags::MS_RELATIME,
            "strictatime" => flags |= MsFlags::MS_STRICTATIME,
            other => data_options.push(other),
        }
    }
    (flags, data_options)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn bind_flag_is_parsed() {
        let opts: Vec<String> = vec!["bind".into(), "foo=bar".into()];
        let (flags, data) = parse_mount_options(&opts);
        assert!(flags.contains(MsFlags::MS_BIND));
        assert_eq!(data, ["foo=bar"]);
    }

    #[test]
    fn loop_is_not_passed_to_kernel() {
        let opts: Vec<String> = vec!["ro".into(), "loop".into()];
        let (flags, data) = parse_mount_options(&opts);
        assert!(flags.contains(MsFlags::MS_RDONLY));
        assert!(data.is_empty());
    }

    #[test]
    fn join_root_handles_slash() {
        assert_eq!(join_root(Path::new("/mnt"), "/"), PathBuf::from("/mnt"));
        assert_eq!(
            join_root(Path::new("/mnt"), "/a/b"),
            PathBuf::from("/mnt/a/b")
        );
    }

    #[test]
    fn device_paths_are_resolved() {
        assert_eq!(
            resolve_device_path("LABEL=NEET_LIVE"),
            PathBuf::from("/dev/disk/by-label/NEET_LIVE")
        );
        assert_eq!(resolve_device_path("/dev/sda1"), PathBuf::from("/dev/sda1"));
    }
}
