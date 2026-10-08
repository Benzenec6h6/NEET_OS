//! 外部コマンド列の組み立て（純粋関数）と実行ヘルパー

use crate::err;
use crate::layout::Extent;
use crate::plan::{Content, FsKind, Partition};
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

#[derive(Debug, Clone, PartialEq, Eq)]
pub struct Cmd {
    pub prog: String,
    pub args: Vec<String>,
}

impl Cmd {
    pub fn new<S: Into<String>>(prog: &str, args: impl IntoIterator<Item = S>) -> Self {
        Cmd {
            prog: prog.to_string(),
            args: args.into_iter().map(Into::into).collect(),
        }
    }

    /// dry-run 表示用（コピペして実行できる形）
    pub fn render(&self) -> String {
        let q = |s: &str| {
            if !s.is_empty()
                && s.chars()
                    .all(|c| c.is_ascii_alphanumeric() || "_./=:@%+-,".contains(c))
            {
                s.to_string()
            } else {
                format!("'{}'", s.replace('\'', r"'\''"))
            }
        };
        std::iter::once(self.prog.as_str())
            .chain(self.args.iter().map(String::as_str))
            .map(q)
            .collect::<Vec<_>>()
            .join(" ")
    }

    pub fn run(&self) -> io::Result<()> {
        println!("disk-setup: $ {}", self.render());
        let status = Command::new(&self.prog)
            .args(&self.args)
            .status()
            .map_err(|e| err(format!("failed to spawn {}: {e}", self.prog)))?;
        if status.success() {
            Ok(())
        } else {
            Err(err(format!("`{}` exited with {status}", self.render())))
        }
    }
}

/// /dev/nvme0n1 -> /dev/nvme0n1p1、/dev/sda -> /dev/sda1
/// 引数は canonicalize 済みの実デバイスパスであること（by-id のままだと規則が違う）
pub fn partition_path(real_device: &str, n: usize) -> String {
    if real_device.ends_with(|c: char| c.is_ascii_digit()) {
        format!("{real_device}p{n}")
    } else {
        format!("{real_device}{n}")
    }
}

/// GPT を作り直すコマンド。パーティション番号は並び順（1 始まり）
pub fn partition_cmds(device: &str, parts: &[Partition], extents: &[Extent]) -> Vec<Cmd> {
    let mut args: Vec<String> = Vec::new();
    for (i, (p, e)) in parts.iter().zip(extents).enumerate() {
        let n = i + 1;
        args.push(format!("--new={n}:{}:{}", e.start_sector, e.end_sector));
        args.push(format!("--typecode={n}:{}", p.type_code));
        args.push(format!("--change-name={n}:{}", p.name));
        args.push(format!("--partition-guid={n}:{}", p.guid));
    }
    args.push(device.to_string());
    vec![
        Cmd::new("sgdisk", ["--zap-all", device]),
        Cmd::new("sgdisk", args),
    ]
}

/// mkfs（swap は mkswap）。
///
/// `rootdir` は mkfs 時に流し込む中身。btrfs では subvolume 名のディレクトリを含んでいること
/// （`--subvol` はディレクトリを subvolume として作る）。ext4 は `-d` に使う。
/// vfat は mkfs では流し込めないので `vfat_populate_cmd` を併用する。
pub fn mkfs_cmds(device: &str, c: &Content, rootdir: Option<&Path>) -> Vec<Cmd> {
    let mut a: Vec<String> = Vec::new();
    let prog = match c.kind {
        FsKind::Vfat => {
            a.extend(
                ["-F", "32", "-n", &c.label, "-i", &c.uuid.replace('-', "")].map(String::from),
            );
            "mkfs.vfat"
        }
        FsKind::Ext4 => {
            a.extend(["-F", "-q", "-L", &c.label, "-U", &c.uuid].map(String::from));
            if let Some(d) = rootdir {
                a.extend(["-d".into(), d.display().to_string()]);
            }
            "mkfs.ext4"
        }
        FsKind::Btrfs => {
            a.extend(["-f", "-L", &c.label, "-U", &c.uuid].map(String::from));
            if let Some(d) = rootdir {
                a.extend(["-r".into(), d.display().to_string()]);
                for sv in &c.subvolumes {
                    a.extend(["--subvol".into(), sv.name.clone()]);
                }
            }
            "mkfs.btrfs"
        }
        FsKind::Swap => {
            a.extend(["-L", &c.label, "-U", &c.uuid].map(String::from));
            "mkswap"
        }
        // ★ 追加: LUKS 自体は mkfs ではなく luks_format_cmd を使うため空を返す
        FsKind::Luks => return vec![],
    };
    a.extend(c.mkfs_args.iter().cloned());
    a.push(device.to_string());
    vec![Cmd::new(prog, a)]
}

/// mkfs 済みの vfat イメージへ `dir` の中身を書き込む（空なら None）
pub fn vfat_populate_cmd(image: &Path, dir: &Path) -> io::Result<Option<Cmd>> {
    let mut entries: Vec<String> = fs::read_dir(dir)?
        .filter_map(|e| e.ok())
        .map(|e| e.path().display().to_string())
        .collect();
    if entries.is_empty() {
        return Ok(None);
    }
    entries.sort();
    let mut args = vec![
        "-i".to_string(),
        image.display().to_string(),
        "-s".into(),
        "-m".into(),
    ];
    args.extend(entries);
    args.push("::/".into());
    Ok(Some(Cmd::new("mcopy", args)))
}

pub fn luks_format_cmd(device: &str, c: &Content) -> Cmd {
    let mut args = vec![
        "luksFormat".to_string(),
        "--type".to_string(),
        "luks2".to_string(),
        "--uuid".to_string(),
        c.uuid.clone(),
    ];
    args.extend(c.extra_luks_args.iter().cloned());
    args.push(device.to_string());
    Cmd::new("cryptsetup", args)
}

pub fn luks_open_cmd(device: &str, name: &str) -> Cmd {
    Cmd::new("cryptsetup", ["open", device, name])
}

pub fn luks_close_cmd(name: &str) -> Cmd {
    Cmd::new("cryptsetup", ["close", name])
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::plan::tests::sample;

    #[test]
    fn partition_paths() {
        assert_eq!(partition_path("/dev/sda", 2), "/dev/sda2");
        assert_eq!(partition_path("/dev/nvme0n1", 1), "/dev/nvme0n1p1");
        assert_eq!(partition_path("/dev/loop0", 3), "/dev/loop0p3");
    }

    #[test]
    fn sgdisk_args() {
        let p = sample();
        let d = &p.disks[0];
        let ext = [
            Extent {
                start_sector: 2048,
                end_sector: 1050623,
            },
            Extent {
                start_sector: 1050624,
                end_sector: 9999999,
            },
        ];
        let cmds = partition_cmds("/dev/x", &d.partitions, &ext);
        assert_eq!(cmds[0].args, ["--zap-all", "/dev/x"]);
        assert!(cmds[1].args.contains(&"--new=1:2048:1050623".to_string()));
        assert!(cmds[1].args.contains(&"--typecode=2:8300".to_string()));
        assert!(cmds[1].args.contains(&"--change-name=1:esp".to_string()));
        assert_eq!(cmds[1].args.last().unwrap(), "/dev/x");
    }

    #[test]
    fn mkfs_variants() {
        let p = sample();
        let vfat = p.disks[0].partitions[0].content.as_ref().unwrap();
        let c = &mkfs_cmds("/dev/p1", vfat, None)[0];
        assert_eq!(c.prog, "mkfs.vfat");
        assert!(c.args.windows(2).any(|w| w == ["-i", "ABCD1234"]));

        let btrfs = p.disks[0].partitions[1].content.as_ref().unwrap();
        let c = &mkfs_cmds("/dev/p2", btrfs, Some(Path::new("/stage")))[0];
        assert_eq!(c.prog, "mkfs.btrfs");
        let r = c.render();
        assert!(
            r.contains("-r /stage --subvol @root --subvol @nix --subvol @scratch /dev/p2"),
            "{r}"
        );
    }

    #[test]
    fn render_quotes() {
        let c = Cmd::new("echo", ["a b", "it's"]);
        assert_eq!(c.render(), r#"echo 'a b' 'it'\''s'"#);
    }
}
