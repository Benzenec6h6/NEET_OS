//! init-core: mount-plan.json の解釈とマウント実行（stage1 / stage2 共通）
//!
//! 方針:
//! - bind マウントの失敗は致命的エラーとして呼び出し側に返す
//!   （黙って続行すると、書き込みが揮発するルート側に入りデータを失うため）
//! - btrfs の resetOnBoot は旧ルートを削除せず `old_roots/` に退避し、
//!   `keepOldRoots` 世代を超えたものだけを古い順に削除する

use nix::mount::{mount, umount, MsFlags};
use serde::Deserialize;
use std::collections::HashMap;
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

/// btrfs トップレベル (subvolid=5) を一時マウントする場所
const BTRFS_TMP_MNT: &str = "/tmp_btrfs_reset";
/// 旧ルートの退避先（トップレベル直下）
const OLD_ROOTS_DIR: &str = "old_roots";
const DEFAULT_KEEP_OLD_ROOTS: u32 = 3;

fn default_keep_old_roots() -> u32 {
    DEFAULT_KEEP_OLD_ROOTS
}

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
    #[serde(rename = "resetOnBoot", default)]
    pub reset_on_boot: bool,
    /// btrfs リセット時に残す旧ルートの世代数（0 なら退避せず即削除）
    #[serde(rename = "keepOldRoots", default = "default_keep_old_roots")]
    pub keep_old_roots: u32,
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
    sort_entries(&mut entries);
    Ok(entries)
}

/// 親が必ず子より先になるよう、パスの階層数（同数なら名前）で並べる
fn sort_entries(entries: &mut [MountEntry]) {
    entries.sort_by_key(|e| {
        (
            Path::new(&e.mount_point).components().count(),
            e.mount_point.clone(),
        )
    });
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

fn fatal(msg: String) -> io::Error {
    io::Error::new(io::ErrorKind::Other, msg)
}

/// root: マウント先のプレフィックス。stage1 なら "/mnt"、stage2 なら "/" を渡す。
///
/// bind マウントの失敗、btrfs リセットの失敗は `Err` を返す。
/// それ以外のマウント失敗は警告に留めて続行する。
pub fn apply_plan(entries: &[MountEntry], root: &Path, strict: bool) -> io::Result<()> {
    for entry in entries {
        if entry.already_mounted {
            println!("init-core: skipping already mounted {}", entry.mount_point);
            continue;
        }

        let target = join_root(root, &entry.mount_point);
        let (flags, data_options) = parse_mount_options(&entry.options);
        let is_bind = flags.contains(MsFlags::MS_BIND);

        // bind のソースは root 配下のパス、それ以外は UUID= 等を解決したデバイスパス
        let source = if is_bind {
            join_root(root, &entry.device)
        } else {
            resolve_device_path(&entry.device)
        };

        entry.wait_device(&source);

        // bind のソースが無いと mount が失敗するので事前に作る
        if is_bind && !source.exists() {
            println!(
                "init-core: creating bind source directory {}",
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
                    "init-core: resetting btrfs subvolume for {} (keep {} old roots)",
                    entry.mount_point, entry.keep_old_roots
                );
                reset_btrfs_subvolume(&source, &entry.options, entry.keep_old_roots).map_err(
                    |e| {
                        fatal(format!(
                            "FATAL: failed to reset btrfs subvolume for {}: {e}",
                            entry.mount_point
                        ))
                    },
                )?;
            } else {
                eprintln!(
                    "init-core: warning: resetOnBoot is only supported for btrfs (ignored for {} on {})",
                    entry.fs_type, entry.mount_point
                );
            }
        }

        println!(
            "init-core: mounting {} ({}) on {} ({})",
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
            eprintln!("init-core: warning: {msg}");
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
                eprintln!("init-core: warning: {msg}");
            }
        }
    }
    Ok(())
}

// ---------------------------------------------------------------------------
// btrfs リセット
// ---------------------------------------------------------------------------

/// Btrfs のサブボリュームを、旧ルートを退避したうえで空の状態で再作成する
fn reset_btrfs_subvolume(dev_path: &Path, options: &[String], keep: u32) -> io::Result<()> {
    let subvol = options
        .iter()
        .find_map(|opt| opt.strip_prefix("subvol="))
        .ok_or_else(|| {
            io::Error::new(
                io::ErrorKind::InvalidInput,
                "btrfs reset requires subvol= option",
            )
        })?
        .trim_start_matches('/');

    // 空文字やトップレベル全体、".." を含むパスは絶対に対象にしない
    if subvol.is_empty()
        || !Path::new(subvol)
            .components()
            .all(|c| matches!(c, Component::Normal(_)))
    {
        return Err(io::Error::new(
            io::ErrorKind::InvalidInput,
            format!("refusing to reset unsafe subvolume path '{subvol}'"),
        ));
    }

    let tmp_mnt = Path::new(BTRFS_TMP_MNT);
    fs::create_dir_all(tmp_mnt)?;

    mount(
        Some(dev_path),
        tmp_mnt,
        Some("btrfs"),
        MsFlags::empty(),
        Some("subvolid=5"),
    )
    .map_err(|e| {
        fatal(format!(
            "failed to mount btrfs top-level of {}: {e}",
            dev_path.display()
        ))
    })?;

    let result = rotate_and_recreate(tmp_mnt, subvol, keep);

    if let Err(e) = umount(tmp_mnt) {
        eprintln!("init-core: warning: failed to unmount {BTRFS_TMP_MNT}: {e}");
    }
    let _ = fs::remove_dir(tmp_mnt);

    result
}

/// 旧ルートを退避 → 新規作成 → 世代超過分を削除
///
/// 新規作成が成功してから削除に入るので、削除側の失敗はブートを止めない。
/// 退避後に作成が失敗した場合も、旧ルートは old_roots に残っている。
fn rotate_and_recreate(top: &Path, subvol: &str, keep: u32) -> io::Result<()> {
    let target = top.join(subvol);
    let store = top.join(OLD_ROOTS_DIR).join(subvol.replace('/', "_"));

    if target.exists() {
        fs::create_dir_all(&store)?;
        let seq = next_seq(&list_generations(&store)?);
        let dest = store.join(format!("{seq:06}"));
        fs::rename(&target, &dest)?;
        println!("init-core: moved old root to {}", dest.display());
    }

    if let Some(parent) = target.parent() {
        fs::create_dir_all(parent)?;
    }
    run(Command::new("btrfs")
        .args(["subvolume", "create"])
        .arg(&target))?;

    if store.exists() {
        match list_generations(&store) {
            Ok(gens) => {
                for seq in prune_candidates(&gens, keep) {
                    let path = store.join(format!("{seq:06}"));
                    println!("init-core: removing old root {}", path.display());
                    if let Err(e) = delete_subvolume_recursive(top, &path) {
                        eprintln!(
                            "init-core: warning: failed to delete {}: {e}",
                            path.display()
                        );
                    }
                }
            }
            Err(e) => eprintln!("init-core: warning: failed to list old roots: {e}"),
        }
    }
    Ok(())
}

/// store 配下の世代番号一覧
fn list_generations(store: &Path) -> io::Result<Vec<u64>> {
    Ok(fs::read_dir(store)?
        .filter_map(|e| e.ok())
        .filter_map(|e| e.file_name().to_str()?.parse::<u64>().ok())
        .collect())
}

/// 時計が当てにならない initrd でも安全なように、時刻ではなく連番で世代を管理する
fn next_seq(existing: &[u64]) -> u64 {
    existing.iter().max().map_or(1, |m| m + 1)
}

/// 残す世代数 keep を超えた分（古い方から）を返す
fn prune_candidates(existing: &[u64], keep: u32) -> Vec<u64> {
    let mut sorted = existing.to_vec();
    sorted.sort_unstable();
    let excess = sorted.len().saturating_sub(keep as usize);
    sorted.truncate(excess);
    sorted
}

/// ネストしたサブボリュームを深い方から削除し、最後に本体を削除する
fn delete_subvolume_recursive(top: &Path, subvol_path: &Path) -> io::Result<()> {
    let out = Command::new("btrfs")
        .args(["subvolume", "list", "-o"])
        .arg(subvol_path)
        .output()?;

    if out.status.success() {
        let text = String::from_utf8_lossy(&out.stdout);
        let mut nested: Vec<PathBuf> = text
            .lines()
            .filter_map(|l| l.split_once(" path ").map(|(_, p)| p.trim()))
            .map(|p| top.join(p.trim_start_matches("<FS_TREE>/")))
            .collect();
        nested.sort_by_key(|p| std::cmp::Reverse(p.components().count()));
        for p in nested {
            run(Command::new("btrfs").args(["subvolume", "delete"]).arg(&p))?;
        }
    }

    run(Command::new("btrfs")
        .args(["subvolume", "delete"])
        .arg(subvol_path))
}

fn run(cmd: &mut Command) -> io::Result<()> {
    let status = cmd.status()?;
    if status.success() {
        Ok(())
    } else {
        Err(fatal(format!("{cmd:?} exited with {status}")))
    }
}

// ---------------------------------------------------------------------------
// ユーティリティ
// ---------------------------------------------------------------------------

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

#[cfg(test)]
mod tests {
    use super::*;

    fn entry(mp: &str) -> MountEntry {
        serde_json::from_str(&format!(
            r#"{{"device":"x","mountPoint":"{mp}","fsType":"none"}}"#
        ))
        .unwrap()
    }

    #[test]
    fn keep_old_roots_defaults_to_three() {
        assert_eq!(entry("/a").keep_old_roots, 3);
        let e: MountEntry = serde_json::from_str(
            r#"{"device":"x","mountPoint":"/","fsType":"btrfs","keepOldRoots":0}"#,
        )
        .unwrap();
        assert_eq!(e.keep_old_roots, 0);
    }

    #[test]
    fn parents_are_mounted_before_children() {
        let mut v = vec![
            entry("/var/log/journal"),
            entry("/var/log"),
            entry("/"),
            entry("/var"),
        ];
        sort_entries(&mut v);
        let order: Vec<_> = v.iter().map(|e| e.mount_point.as_str()).collect();
        assert_eq!(order, ["/", "/var", "/var/log", "/var/log/journal"]);
    }

    #[test]
    fn seq_and_pruning() {
        assert_eq!(next_seq(&[]), 1);
        assert_eq!(next_seq(&[1, 5, 3]), 6);
        assert_eq!(prune_candidates(&[3, 1, 2, 4], 2), vec![1, 2]);
        assert_eq!(prune_candidates(&[1, 2], 3), Vec::<u64>::new());
        assert_eq!(prune_candidates(&[1, 2], 0), vec![1, 2]);
    }

    #[test]
    fn bind_flag_is_parsed() {
        let opts: Vec<String> = vec!["bind".into(), "foo=bar".into()];
        let (flags, data) = parse_mount_options(&opts);
        assert!(flags.contains(MsFlags::MS_BIND));
        assert_eq!(data, ["foo=bar"]);
    }

    #[test]
    fn join_root_handles_slash() {
        assert_eq!(join_root(Path::new("/mnt"), "/"), PathBuf::from("/mnt"));
        assert_eq!(
            join_root(Path::new("/mnt"), "/a/b"),
            PathBuf::from("/mnt/a/b")
        );
    }
}
