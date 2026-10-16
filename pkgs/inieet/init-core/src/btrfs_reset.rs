//! btrfs サブボリュームの退避と再作成（resetOnBoot の実体）
//!
//! マウントやプランには依存しない。入力はデバイス・options・保持世代数だけ。

use crate::util::{fatal, run};
use nix::mount::{mount, umount, MsFlags};
use std::fs;
use std::io;
use std::path::{Component, Path, PathBuf};
use std::process::Command;

/// btrfs トップレベル (subvolid=5) を一時マウントする場所
const BTRFS_TMP_MNT: &str = "/tmp_btrfs_reset";
/// 旧ルートの退避先（トップレベル直下）
const OLD_ROOTS_DIR: &str = "old_roots";

/// Btrfs のサブボリュームを、旧ルートを退避したうえで空の状態で再作成する
pub(crate) fn reset_subvolume(dev_path: &Path, options: &[String], keep: u32) -> io::Result<()> {
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

    // 結果の成否にかかわらず、この後で必ず umount する
    let result = guard_and_rotate(tmp_mnt, subvol, keep);

    if let Err(e) = umount(tmp_mnt) {
        eprintln!("init-core: warning: failed to unmount {BTRFS_TMP_MNT}: {e}");
    }
    let _ = fs::remove_dir(tmp_mnt);

    result
}

/// 退避対象の中に実体の /nix/store が入っていないか検証してから、ローテーションする
fn guard_and_rotate(top: &Path, subvol: &str, keep: u32) -> io::Result<()> {
    // もしマウント計画に独立した /nix がないのに、ここに nix/store があるなら絶対に動かしてはいけない
    if top.join(subvol).join("nix/store").exists() {
        return Err(fatal(format!(
            "REFUSING to reset subvolume '{subvol}': it contains '/nix/store'! \
            Moving this subvolume will destroy the operating system. \
            Ensure '/nix' is mounted from a separate subvolume."
        )));
    }
    rotate_and_recreate(top, subvol, keep)
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn seq_and_pruning() {
        assert_eq!(next_seq(&[]), 1);
        assert_eq!(next_seq(&[1, 5, 3]), 6);
        assert_eq!(prune_candidates(&[3, 1, 2, 4], 2), vec![1, 2]);
        assert_eq!(prune_candidates(&[1, 2], 3), Vec::<u64>::new());
        assert_eq!(prune_candidates(&[1, 2], 0), vec![1, 2]);
    }

    #[test]
    fn unsafe_subvol_paths_are_rejected() {
        let dev = Path::new("/dev/null");
        for bad in ["subvol=", "subvol=/", "subvol=../x", "subvol=a/../b"] {
            let r = reset_subvolume(dev, &[bad.to_string()], 3);
            assert!(r.is_err(), "{bad} should be rejected");
        }
    }
}
