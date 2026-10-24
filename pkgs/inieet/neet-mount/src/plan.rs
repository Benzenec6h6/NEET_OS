//! mount-plan.json の読み込みと、マウント順序の決定

use crate::util::fatal;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::io;
use std::path::Path;

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
    /// 先にマウントされていなければならないエントリの mountPoint
    #[serde(default)]
    pub requires: Vec<String>,
    /// true なら mountPoint を root 配下ではなく initrd の絶対パスとして扱う（足場用）
    #[serde(rename = "outsideRoot", default)]
    pub outside_root: bool,
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
}

pub fn load_plan(plan_path: &Path) -> io::Result<Vec<MountEntry>> {
    let data = fs::read_to_string(plan_path)?;
    let plan: HashMap<String, MountEntry> =
        serde_json::from_str(&data).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
    let mut entries: Vec<MountEntry> = plan.into_values().collect();
    sort_entries(&mut entries)?;
    Ok(entries)
}

/// 足場(outsideRoot)を先頭に、残りは階層の浅い順（同数なら名前）。
/// そのうえで requires を満たす順に並べ直す。
fn sort_entries(entries: &mut Vec<MountEntry>) -> io::Result<()> {
    entries.sort_by_key(|e| {
        (
            !e.outside_root,
            Path::new(&e.mount_point).components().count(),
            e.mount_point.clone(),
        )
    });

    {
        let known: HashSet<&str> = entries.iter().map(|e| e.mount_point.as_str()).collect();
        for e in entries.iter() {
            for r in &e.requires {
                if !known.contains(r.as_str()) {
                    return Err(fatal(format!(
                        "{} requires unknown mount point {r}",
                        e.mount_point
                    )));
                }
            }
        }
    }

    let mut pending = std::mem::take(entries);
    let mut done: HashSet<String> = HashSet::new();
    while !pending.is_empty() {
        let Some(i) = pending
            .iter()
            .position(|e| e.requires.iter().all(|r| done.contains(r)))
        else {
            let stuck: Vec<_> = pending.iter().map(|e| e.mount_point.as_str()).collect();
            return Err(fatal(format!(
                "circular requires among: {}",
                stuck.join(", ")
            )));
        };
        let e = pending.remove(i);
        done.insert(e.mount_point.clone());
        entries.push(e);
    }
    Ok(())
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

    fn scaffold(mp: &str, requires: &[&str]) -> MountEntry {
        let mut e = entry(mp);
        e.outside_root = true;
        e.requires = requires.iter().map(|s| s.to_string()).collect();
        e
    }

    #[test]
    fn scaffolding_is_mounted_before_root() {
        let mut root = entry("/");
        root.requires = vec!["/run/live/squash".into()];
        let mut v = vec![
            entry("/boot"),
            root,
            scaffold("/run/live/squash", &["/run/live/iso"]),
            scaffold("/run/live/iso", &[]),
        ];
        sort_entries(&mut v).unwrap();
        let order: Vec<_> = v.iter().map(|e| e.mount_point.as_str()).collect();
        assert_eq!(order, ["/run/live/iso", "/run/live/squash", "/", "/boot"]);
    }

    #[test]
    fn circular_requires_is_error() {
        let mut v = vec![scaffold("/a", &["/b"]), scaffold("/b", &["/a"])];
        assert!(sort_entries(&mut v).is_err());
    }

    #[test]
    fn unknown_require_is_error() {
        let mut v = vec![scaffold("/a", &["/nope"])];
        assert!(sort_entries(&mut v).is_err());
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
        sort_entries(&mut v).unwrap();
        let order: Vec<_> = v.iter().map(|e| e.mount_point.as_str()).collect();
        assert_eq!(order, ["/", "/var", "/var/log", "/var/log/journal"]);
    }
}
