use nix::mount::{mount, MsFlags};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};
use std::thread;
use std::time::Duration;

#[derive(Debug, Deserialize, Clone)]
pub struct MountEntry {
    pub device: String,
    #[serde(rename = "mountPoint")]
    pub mount_point: String,
    #[serde(rename = "fsType")]
    pub fs_type: String,
    #[serde(default)]
    pub options: Vec<String>,
    #[serde(rename = "alreadyMounted", default)]
    pub already_mounted: bool,
}

impl MountEntry {
    /// 仮想ファイルシステム（疑似FS）ではなく、実ストレージを待つ必要があるか判定
    pub fn is_physical_device(&self) -> bool {
        let is_virtual = matches!(
            self.fs_type.as_str(),
            "proc"
                | "sysfs"
                | "devtmpfs"
                | "tmpfs"
                | "devpts"
                | "none"
                | "cgroup"
                | "cgroup2"
                | "pstore"
        );
        // 仮想FSでなく、かつ実デバイスパス（UUID=, LABEL=, /dev/... 等）の指定がある場合のみ true
        !is_virtual && (self.device.starts_with('/') || self.device.contains('='))
    }

    /// デバイスの出現を待機し、現れなかった場合は警告を出力する
    pub fn wait_device(&self, dev_path: &Path) {
        if self.is_physical_device() && !wait_for_device(dev_path, Duration::from_secs(3)) {
            eprintln!(
                "init-core: warning: device path {} ({}) did not appear in time",
                dev_path.display(),
                self.device
            );
        }
    }
}

pub fn load_plan(plan_path: &Path) -> io::Result<Vec<MountEntry>> {
    let data = fs::read_to_string(plan_path)?;
    let plan: HashMap<String, MountEntry> =
        serde_json::from_str(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut entries: Vec<MountEntry> = plan.into_values().collect();
    // 深さ順ソート：階層構造の依存関係順にマウントするため
    entries.sort_by_key(|e| (e.mount_point.len(), e.mount_point.clone()));
    Ok(entries)
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

/// 指定されたデバイスノードが出現するまで待機する関数
fn wait_for_device(dev_path: &Path, timeout: Duration) -> bool {
    let start = std::time::Instant::now();
    while start.elapsed() < timeout {
        if dev_path.exists() {
            return true;
        }
        thread::sleep(Duration::from_millis(50));
    }
    dev_path.exists()
}

/// root: マウント先のプレフィックス。stage1なら "/mnt"、stage2なら "" を渡す。
pub fn apply_plan(entries: &[MountEntry], root: &Path) -> io::Result<()> {
    for entry in entries {
        if entry.already_mounted {
            println!("init-core: skipping already mounted {}", entry.mount_point);
            continue;
        }
        let target = join_root(root, &entry.mount_point);
        let dev_path = resolve_device_path(&entry.device);

        // 実デバイスのみ待機（仮想FSはスキップ）
        entry.wait_device(&dev_path);

        println!(
            "init-core: mounting {} ({}) on {} ({})",
            entry.device,
            dev_path.display(),
            target.display(),
            entry.fs_type
        );

        if let Err(e) = fs::create_dir_all(&target) {
            eprintln!(
                "init-core: warning: failed to create {}: {}",
                target.display(),
                e
            );
            continue;
        }

        let (flags, data_options) = parse_mount_options(&entry.options);
        let data_str = (!data_options.is_empty()).then(|| data_options.join(","));
        let result = mount(
            Some(&dev_path),
            &target,
            Some(entry.fs_type.as_str()),
            flags,
            data_str.as_deref(),
        );

        match result {
            Ok(_) | Err(nix::errno::Errno::EBUSY) => {}
            Err(e) => eprintln!(
                "init-core: warning: failed to mount {} ({}): {}",
                target.display(),
                entry.device,
                e
            ),
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
