//! 実機に対する format / mount

use crate::err;
use crate::layout::{compute_layout, parse_size, Extent};
use crate::plan::{Disk, FsKind, Plan};
use crate::steps::{
    luks_format_cmd, luks_open_cmd, mkfs_cmds, partition_cmds, partition_path, Cmd,
};
use std::fs;
use std::io;
use std::os::unix::fs::FileTypeExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::thread;
use std::time::{Duration, Instant};

pub struct FormatOpts {
    /// plan の device を上書き
    pub device: Option<String>,
    /// これが無ければ dry-run（何も変更せず、実行内容を表示するだけ）
    pub yes: bool,
    /// 既存のシグネチャ（ファイルシステム/パーティションテーブル）があっても続行
    pub force: bool,
}

fn blockdev(flag: &str, dev: &str) -> io::Result<u64> {
    let out = Command::new("blockdev").args([flag, dev]).output()?;
    if !out.status.success() {
        return Err(err(format!("blockdev {flag} {dev} failed")));
    }
    String::from_utf8_lossy(&out.stdout)
        .trim()
        .parse()
        .map_err(|_| err("unexpected blockdev output"))
}

/// `dev` 自身、またはその配下のパーティションか
fn belongs_to(dev: &str, source: &str) -> bool {
    match source.strip_prefix(dev) {
        Some("") => true,
        Some(rest) => {
            let rest = rest.strip_prefix('p').unwrap_or(rest);
            !rest.is_empty() && rest.chars().all(|c| c.is_ascii_digit())
        }
        None => false,
    }
}

fn mounted_from(dev: &str) -> io::Result<Option<String>> {
    let mounts = fs::read_to_string("/proc/mounts")?;
    Ok(mounts
        .lines()
        .filter_map(|l| l.split_whitespace().next())
        .find(|src| belongs_to(dev, src))
        .map(String::from))
}

/// 既存のシグネチャ（wipefs --no-act は何も変更しない）
fn existing_signatures(dev: &str) -> io::Result<String> {
    let out = Command::new("wipefs").args(["--no-act", dev]).output()?;
    Ok(String::from_utf8_lossy(&out.stdout).trim().to_string())
}

fn wait_for(path: &str, timeout: Duration) -> bool {
    let start = Instant::now();
    while start.elapsed() < timeout {
        if Path::new(path).exists() {
            return true;
        }
        thread::sleep(Duration::from_millis(100));
    }
    Path::new(path).exists()
}

pub fn extents_for(disk: &Disk, total_bytes: u64, sector: u64) -> io::Result<Vec<Extent>> {
    let specs = disk
        .partitions
        .iter()
        .map(|p| parse_size(&p.size))
        .collect::<Result<Vec<_>, _>>()
        .map_err(err)?;
    compute_layout(total_bytes, sector, &specs).map_err(err)
}

/// btrfs の mkfs に渡す rootdir（subvolume 名の空ディレクトリを持つ一時ディレクトリ）
fn btrfs_roots(disk: &Disk, base: &Path) -> Vec<(usize, PathBuf)> {
    disk.partitions
        .iter()
        .enumerate()
        .filter(|(_, p)| {
            p.content.as_ref().is_some_and(|c| {
                // LUKS の場合は内部を見る
                let target = if c.kind == FsKind::Luks {
                    c.content.as_deref()
                } else {
                    Some(c)
                };
                target.is_some_and(|tc| tc.kind == FsKind::Btrfs && !tc.subvolumes.is_empty())
            })
        })
        .map(|(i, _)| (i, base.join(format!("part-{}", i + 1))))
        .collect()
}

pub fn format_disk(disk: &Disk, o: &FormatOpts) -> io::Result<()> {
    let dev_arg = o
        .device
        .clone()
        .or_else(|| disk.device.clone())
        .ok_or_else(|| err(format!("disk '{}': no device; pass --device", disk.name)))?;
    let real = fs::canonicalize(&dev_arg)
        .map_err(|e| err(format!("cannot resolve {dev_arg}: {e}")))?
        .display()
        .to_string();
    if !fs::metadata(&real)?.file_type().is_block_device() {
        return Err(err(format!("{real} is not a block device")));
    }
    if let Some(src) = mounted_from(&real)? {
        return Err(err(format!("{src} is mounted; refusing to touch {real}")));
    }

    let total = blockdev("--getsize64", &real)?;
    let sector = blockdev("--getss", &real)?;
    let extents = extents_for(disk, total, sector)?;

    let tmp_base = std::env::temp_dir().join(format!("disk-setup-{}", std::process::id()));
    let roots = btrfs_roots(disk, &tmp_base);

    let part_cmds = partition_cmds(&real, &disk.partitions, &extents);
    let mut fs_cmds: Vec<Cmd> = Vec::new();
    for (i, p) in disk.partitions.iter().enumerate() {
        let node = partition_path(&real, i + 1);
        fs_cmds.push(Cmd::new("wipefs", ["--all", &node]));
        if let Some(c) = &p.content {
            let rootdir = roots
                .iter()
                .find(|(j, _)| *j == i)
                .map(|(_, d)| d.as_path());
            // ★ LUKS の場合は luksFormat -> open -> 内部 mkfs を順に並べる
            if c.kind == FsKind::Luks {
                let luks_name = c.luks_name.as_deref().unwrap_or("cryptroot");
                let mapper_dev = format!("/dev/mapper/{luks_name}");
                fs_cmds.push(luks_format_cmd(&node, c));
                fs_cmds.push(luks_open_cmd(&node, luks_name));
                if let Some(inner) = &c.content {
                    fs_cmds.extend(mkfs_cmds(&mapper_dev, inner, rootdir));
                }
            } else {
                fs_cmds.extend(mkfs_cmds(&node, c, rootdir));
            }
        }
    }

    println!(
        "disk-setup: target {dev_arg} -> {real} ({} bytes, sector {sector})",
        total
    );
    let sigs = existing_signatures(&real)?;
    if !sigs.is_empty() {
        println!("disk-setup: WARNING existing signatures found:\n{sigs}");
    }
    for c in part_cmds.iter().chain(&fs_cmds) {
        println!("  $ {}", c.render());
    }
    if !o.yes {
        println!("disk-setup: dry-run (nothing changed). re-run with --yes to apply.");
        return Ok(());
    }
    if !sigs.is_empty() && !o.force {
        return Err(err("existing signatures found; refusing without --force"));
    }

    for (i, dir) in &roots {
        if let Some(c) = &disk.partitions[*i].content {
            let target = if c.kind == FsKind::Luks {
                c.content.as_deref()
            } else {
                Some(c)
            };
            if let Some(target) = target {
                for sv in &target.subvolumes {
                    fs::create_dir_all(dir.join(&sv.name))?;
                }
            }
        }
    }

    let result = (|| {
        for c in &part_cmds {
            c.run()?;
        }
        // カーネルにパーティションテーブルを読み直させ、ノードの出現を待つ
        let _ = Command::new("blockdev")
            .args(["--rereadpt", &real])
            .status();
        for i in 0..disk.partitions.len() {
            let node = partition_path(&real, i + 1);
            if !wait_for(&node, Duration::from_secs(10)) {
                return Err(err(format!("partition node {node} did not appear")));
            }
        }
        for c in &fs_cmds {
            c.run()?;
        }
        // mdevd-disk.sh は add/change で by-uuid/by-label を作る。mkfs は uevent を出さないので、
        // 作成後に change を発行してリンクを張らせる（失敗しても致命的ではない）
        for i in 0..disk.partitions.len() {
            let node = partition_path(&real, i + 1);
            if let Some(name) = Path::new(&node).file_name() {
                let ue = Path::new("/sys/class/block").join(name).join("uevent");
                if let Err(e) = fs::write(&ue, "change") {
                    eprintln!(
                        "disk-setup: warning: could not trigger {}: {e}",
                        ue.display()
                    );
                }
            }
        }
        Ok(())
    })();
    let _ = fs::remove_dir_all(&tmp_base);
    result
}

/// plan の全ファイルシステムを `root` 配下へマウントする（インストール用）。
/// マウントの実処理は init-core に委譲する。resetOnBoot は意図的に無効（インストール中に消さない）
pub fn mount_plan(
    plan: &Plan,
    root: &Path,
    device_override: Option<(&str, &str)>,
) -> io::Result<()> {
    let mut entries: Vec<init_core::MountEntry> = Vec::new();
    for disk in &plan.disks {
        let dev = match device_override {
            Some((name, dev)) if name == disk.name => Some(dev.to_string()),
            _ => disk.device.clone(),
        };
        let real = dev
            .and_then(|d| fs::canonicalize(d).ok())
            .map(|p| p.display().to_string());
        for (i, p) in disk.partitions.iter().enumerate() {
            let Some(c) = &p.content else { continue };
            let part_node = real
                .as_ref()
                .map(|r| partition_path(r, i + 1))
                .unwrap_or_else(|| format!("PARTUUID={}", p.guid));

            // ★ LUKS の場合: 必要に応じてオープンし、mapper デバイスをマウント対象にする
            if c.kind == FsKind::Luks {
                let luks_name = c.luks_name.as_deref().unwrap_or("cryptroot");
                let mapper_path = format!("/dev/mapper/{luks_name}");

                // まだオープンされていなければ cryptsetup open を実行
                if !Path::new(&mapper_path).exists() {
                    println!("disk-setup: opening LUKS device {part_node} -> {luks_name}");
                    luks_open_cmd(&part_node, luks_name).run()?;
                }

                if let Some(inner) = &c.content {
                    for m in inner.mounts() {
                        entries.push(init_core::MountEntry {
                            device: mapper_path.clone(),
                            mount_point: m.mount_point,
                            fs_type: inner.fs_type().to_string(),
                            options: m.options,
                            already_mounted: false,
                            reset_on_boot: false,
                            keep_old_roots: 3,
                        });
                    }
                }
            } else {
                for m in c.mounts() {
                    entries.push(init_core::MountEntry {
                        device: part_node.clone(),
                        mount_point: m.mount_point,
                        fs_type: c.fs_type().to_string(),
                        options: m.options,
                        already_mounted: false,
                        reset_on_boot: false,
                        keep_old_roots: 3,
                    });
                }
            }
        }
    }
    // 親が先（深さ、同数なら名前）
    entries.sort_by_key(|e| {
        (
            Path::new(&e.mount_point).components().count(),
            e.mount_point.clone(),
        )
    });
    init_core::apply_plan(&entries, root, true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn belongs() {
        assert!(belongs_to("/dev/sda", "/dev/sda"));
        assert!(belongs_to("/dev/sda", "/dev/sda2"));
        assert!(belongs_to("/dev/nvme0n1", "/dev/nvme0n1p3"));
        assert!(!belongs_to("/dev/sda", "/dev/sdaa1"));
        assert!(!belongs_to("/dev/sda", "tmpfs"));
        assert!(!belongs_to("/dev/sda", "/dev/sdb1"));
    }
}
