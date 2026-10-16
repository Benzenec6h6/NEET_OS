use sha2::{Digest, Sha256};
use std::ffi::OsString;
use std::fs::{self, File, OpenOptions};
use std::io::{self, Read, Write};
use std::os::unix::fs::{symlink, OpenOptionsExt};
use std::path::{Path, PathBuf};

fn tmp_sibling(path: &Path) -> PathBuf {
    let mut name: OsString = path.file_name().unwrap_or_default().to_os_string();
    name.push(format!(".neet-tmp.{}", std::process::id()));
    path.with_file_name(name)
}

fn sync_parent(path: &Path) -> io::Result<()> {
    match path.parent() {
        Some(p) if !p.as_os_str().is_empty() => File::open(p)?.sync_all(),
        _ => Ok(()),
    }
}

/// link を target への symlink にする。link が symlink/ファイルなら1回の rename で置換。
/// link が実ディレクトリの場合は rename が失敗する (呼び出し側で移行を明示する)。
pub fn atomic_symlink(target: &Path, link: &Path) -> io::Result<()> {
    let tmp = tmp_sibling(link);
    let _ = fs::remove_file(&tmp);
    symlink(target, &tmp)?;
    if let Err(e) = fs::rename(&tmp, link) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    sync_parent(link)
}

/// 内容を mode 付きで作成 → fsync → rename。公開時点で権限は確定している。
pub fn atomic_write(path: &Path, data: &[u8], mode: u32) -> io::Result<()> {
    let tmp = tmp_sibling(path);
    let _ = fs::remove_file(&tmp);
    let res = (|| {
        let mut f = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode)
            .open(&tmp)?;
        f.write_all(data)?;
        f.sync_all()?;
        fs::rename(&tmp, path)
    })();
    if res.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    res?;
    sync_parent(path)
}

pub fn sha256_file(path: &Path) -> io::Result<[u8; 32]> {
    let mut f = File::open(path)?;
    let mut h = Sha256::new();
    let mut buf = [0u8; 64 * 1024];
    loop {
        let n = f.read(&mut buf)?;
        if n == 0 {
            break;
        }
        h.update(&buf[..n]);
    }
    Ok(h.finalize().into())
}

/// src を dst にコピー。内容(ハッシュ)が同じなら何もしない。戻り値は更新したか。
pub fn atomic_copy_if_changed(src: &Path, dst: &Path, mode: u32) -> io::Result<bool> {
    if dst.exists() && sha256_file(src)? == sha256_file(dst)? {
        return Ok(false);
    }
    let tmp = tmp_sibling(dst);
    let _ = fs::remove_file(&tmp);
    let res = (|| {
        let mut input = File::open(src)?;
        let mut out = OpenOptions::new()
            .write(true)
            .create_new(true)
            .mode(mode & 0o7777)
            .open(&tmp)?;
        io::copy(&mut input, &mut out)?;
        out.sync_all()?;
        fs::rename(&tmp, dst)
    })();
    if res.is_err() {
        let _ = fs::remove_file(&tmp);
    }
    res?;
    sync_parent(dst)?;
    Ok(true)
}
