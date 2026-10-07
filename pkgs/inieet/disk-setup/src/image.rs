//! root 権限もループバックも無い環境（Nix サンドボックス）でのディスクイメージ生成
//!
//! 各パーティションを別ファイルとして mkfs（中身を流し込みながら）し、GPT を書いたファイルへ
//! オフセット指定で書き込む。マウントポイントごとの中身は、`--tree` で渡された
//! 「完成後のルート階層」から切り出す（入れ子のマウントポイントは空ディレクトリにして除外）。

use crate::err;
use crate::exec::extents_for;
use crate::plan::{Content, FsKind, Plan};
use crate::steps::{mkfs_cmds, partition_cmds, vfat_populate_cmd, Cmd};
use std::collections::BTreeSet;
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Seek, SeekFrom};
use std::path::{Component, Path, PathBuf};

const SECTOR: u64 = 512;

pub struct ImageOpts {
    pub disk: Option<String>,
    pub size_bytes: u64,
    /// 完成後のルート階層（後ろのものが前を上書き）
    pub trees: Vec<PathBuf>,
    pub out: PathBuf,
    pub work: PathBuf,
}

pub fn build_image(plan: &Plan, o: &ImageOpts) -> io::Result<()> {
    let disk = plan.select_disk(o.disk.as_deref()).map_err(err)?;
    let all_mps = plan.all_mount_points();
    let extents = extents_for(disk, o.size_bytes, SECTOR)?;

    let f = File::create(&o.out)?;
    f.set_len(o.size_bytes)?;
    drop(f);
    fs::create_dir_all(&o.work)?;

    let out = o.out.display().to_string();
    for c in partition_cmds(&out, &disk.partitions, &extents) {
        c.run()?;
    }

    for (i, (p, ext)) in disk.partitions.iter().zip(&extents).enumerate() {
        let Some(c) = &p.content else { continue };
        let img = o.work.join(format!("part-{}.img", i + 1));
        let stage = o.work.join(format!("stage-{}", i + 1));
        println!("disk-setup: building {}/{} ({})", disk.name, p.name, c.fs_type());

        File::create(&img)?.set_len(ext.len_bytes(SECTOR))?;
        fs::create_dir_all(&stage)?;
        stage_content(&o.trees, c, &all_mps, &stage)?;

        let img_s = img.display().to_string();
        for cmd in mkfs_cmds(&img_s, c, Some(&stage)) {
            cmd.run()?;
        }
        if c.kind == FsKind::Vfat {
            if let Some(cmd) = vfat_populate_cmd(&img, &stage)? {
                cmd.run()?;
            }
        }

        write_at(&o.out, ext.offset_bytes(SECTOR), &img)?;
        fs::remove_file(&img)?;
        remove_tree(&stage)?;
    }
    Ok(())
}

/// ファイルシステム 1 つ分の「流し込み用ディレクトリ」を作る
fn stage_content(trees: &[PathBuf], c: &Content, all_mps: &[String], stage: &Path) -> io::Result<()> {
    match c.kind {
        FsKind::Swap => Ok(()),
        // btrfs: subvolume 名のディレクトリの下に、その subvolume の中身を置く
        FsKind::Btrfs if !c.subvolumes.is_empty() => {
            for sv in &c.subvolumes {
                let dir = stage.join(&sv.name);
                match &sv.mount_point {
                    Some(mp) => carve(trees, mp, all_mps, &dir)?,
                    None => fs::create_dir_all(&dir)?,
                }
            }
            Ok(())
        }
        _ => match &c.mount_point {
            Some(mp) => carve(trees, mp, all_mps, stage),
            None => Ok(()),
        },
    }
}

/// `mp` にマウントされるファイルシステムの中身を `dst` に作る
pub fn carve(trees: &[PathBuf], mp: &str, all_mps: &[String], dst: &Path) -> io::Result<()> {
    // mp より下にある他のマウントポイント（mp からの相対パス）
    let nested: Vec<PathBuf> = all_mps
        .iter()
        .filter_map(|m| Path::new(m).strip_prefix(mp).ok())
        .filter(|r| !r.as_os_str().is_empty())
        .map(PathBuf::from)
        .collect();
    let rel = mp.trim_start_matches('/');
    let srcs: Vec<PathBuf> = trees
        .iter()
        .map(|t| if rel.is_empty() { t.clone() } else { t.join(rel) })
        .filter(|p| p.is_dir())
        .collect();
    build_dir(&srcs, dst, Path::new(""), &nested)
}

fn mirror_perms(srcs: &[PathBuf], dst: &Path) -> io::Result<()> {
    if let Some(s) = srcs.last() {
        fs::set_permissions(dst, fs::metadata(s)?.permissions())?;
    }
    Ok(())
}

/// ストアのディレクトリは read-only なので、子を作り終えてから権限を写す
fn build_dir(srcs: &[PathBuf], dst: &Path, rel: &Path, nested: &[PathBuf]) -> io::Result<()> {
    fs::create_dir_all(dst)?;

    let mut names: BTreeSet<OsString> = BTreeSet::new();
    for s in srcs {
        for e in fs::read_dir(s)? {
            names.insert(e?.file_name());
        }
    }
    for n in nested {
        if let Ok(r) = n.strip_prefix(rel) {
            if let Some(Component::Normal(c)) = r.components().next() {
                names.insert(c.to_os_string());
            }
        }
    }

    for name in names {
        let child_rel = rel.join(&name);
        let d_child = dst.join(&name);
        let child_srcs: Vec<PathBuf> = srcs
            .iter()
            .map(|s| s.join(&name))
            .filter(|p| p.symlink_metadata().is_ok())
            .collect();
        let child_dirs = |v: &[PathBuf]| -> Vec<PathBuf> {
            v.iter().filter(|p| p.is_dir() && !p.is_symlink()).cloned().collect()
        };

        if nested.iter().any(|n| *n == child_rel) {
            // 別のファイルシステムのマウントポイント: 空ディレクトリだけ作る
            fs::create_dir_all(&d_child)?;
            mirror_perms(&child_dirs(&child_srcs), &d_child)?;
        } else if nested.iter().any(|n| n.starts_with(&child_rel)) {
            // マウントポイントを含む祖先: 降りて個別に処理
            let dirs = child_dirs(&child_srcs);
            build_dir(&dirs, &d_child, &child_rel, nested)?;
            mirror_perms(&dirs, &d_child)?;
        } else {
            for s in &child_srcs {
                Cmd::new(
                    "cp",
                    ["-a", "-T", "--remove-destination", &s.display().to_string(), &d_child.display().to_string()],
                )
                .run_quiet()?;
            }
        }
    }
    Ok(())
}

impl Cmd {
    /// 大量に呼ばれるコマンド用（ログを出さない）
    fn run_quiet(&self) -> io::Result<()> {
        let st = std::process::Command::new(&self.prog).args(&self.args).status()?;
        if st.success() {
            Ok(())
        } else {
            Err(err(format!("`{}` exited with {st}", self.render())))
        }
    }
}

fn write_at(out: &Path, offset: u64, img: &Path) -> io::Result<()> {
    let mut f = OpenOptions::new().write(true).open(out)?;
    f.seek(SeekFrom::Start(offset))?;
    io::copy(&mut File::open(img)?, &mut f)?;
    f.sync_all()
}

/// read-only なディレクトリを含むので、権限を戻してから消す
fn remove_tree(dir: &Path) -> io::Result<()> {
    Cmd::new("chmod", ["-R", "u+w", &dir.display().to_string()]).run_quiet()?;
    fs::remove_dir_all(dir)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::os::unix::fs::PermissionsExt;

    fn tmp(name: &str) -> PathBuf {
        let d = std::env::temp_dir().join(format!("disk-setup-test-{}-{name}", std::process::id()));
        let _ = fs::remove_dir_all(&d);
        fs::create_dir_all(&d).unwrap();
        d
    }

    #[test]
    fn carve_excludes_nested_mount_points() {
        let t = tmp("carve");
        let tree = t.join("tree");
        fs::create_dir_all(tree.join("nix/store/abc")).unwrap();
        fs::write(tree.join("nix/store/abc/f"), "x").unwrap();
        fs::create_dir_all(tree.join("boot")).unwrap();
        fs::write(tree.join("boot/kernel"), "k").unwrap();
        fs::create_dir_all(tree.join("root")).unwrap();
        fs::write(tree.join("root/.profile"), "p").unwrap();
        // 読み取り専用ディレクトリ（ストア出力を模す）
        fs::set_permissions(tree.join("nix"), fs::Permissions::from_mode(0o555)).unwrap();

        let mps: Vec<String> = ["/", "/nix", "/boot", "/persist"].map(String::from).to_vec();
        let trees = vec![tree.clone()];

        let root = t.join("root-stage");
        carve(&trees, "/", &mps, &root).unwrap();
        assert!(root.join("root/.profile").exists());
        // 入れ子のマウントポイントは空ディレクトリで残り、中身は入らない
        assert!(root.join("nix").is_dir() && !root.join("nix/store").exists());
        assert!(root.join("boot").is_dir() && !root.join("boot/kernel").exists());
        // ツリーに無い /persist も作られる
        assert!(root.join("persist").is_dir());

        let nix = t.join("nix-stage");
        carve(&trees, "/nix", &mps, &nix).unwrap();
        assert!(nix.join("store/abc/f").exists());

        let boot = t.join("boot-stage");
        carve(&trees, "/boot", &mps, &boot).unwrap();
        assert!(boot.join("kernel").exists());

        // 後ろのツリーが前を上書き
        let layer = t.join("layer");
        fs::create_dir_all(layer.join("boot")).unwrap();
        fs::write(layer.join("boot/kernel"), "new").unwrap();
        let boot2 = t.join("boot-stage2");
        carve(&[tree, layer], "/boot", &mps, &boot2).unwrap();
        assert_eq!(fs::read_to_string(boot2.join("kernel")).unwrap(), "new");

        let _ = Cmd::new("chmod", ["-R", "u+w", &t.display().to_string()]).run_quiet();
        let _ = fs::remove_dir_all(&t);
    }
}
