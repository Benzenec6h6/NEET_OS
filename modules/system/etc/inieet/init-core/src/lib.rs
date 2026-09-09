use nix::mount::{mount, MsFlags};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

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

pub fn load_plan(plan_path: &Path) -> io::Result<Vec<MountEntry>> {
    let data = fs::read_to_string(plan_path)?;
    let plan: HashMap<String, MountEntry> =
        serde_json::from_str(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut entries: Vec<MountEntry> = plan.into_values().collect();
    // 深さ順ソート：これがstage1バグの再発防止の要
    entries.sort_by_key(|e| (e.mount_point.len(), e.mount_point.clone()));
    Ok(entries)
}

/// root: マウント先のプレフィックス。stage1なら "/mnt"、stage2なら "" を渡す。
pub fn apply_plan(entries: &[MountEntry], root: &Path) -> io::Result<()> {
    for entry in entries {
        if entry.already_mounted {
            println!("init-core: skipping already mounted {}", entry.mount_point);
            continue;
        }
        let target = join_root(root, &entry.mount_point);
        println!(
            "init-core: mounting {} on {} ({})",
            entry.device,
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
            Some(entry.device.as_str()),
            &target,
            Some(entry.fs_type.as_str()),
            flags,
            data_str.as_deref(),
        );
        if let Err(e) = result {
            if e != nix::errno::Errno::EBUSY {
                eprintln!(
                    "init-core: warning: failed to mount {} ({}): {}",
                    target.display(),
                    entry.device,
                    e
                );
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
    // 既存のfs_setup.rsの実装をそのまま移設
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
