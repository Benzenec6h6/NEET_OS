use std::collections::BTreeSet;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub fn read_clean_manifest(path: &Path) -> BTreeSet<String> {
    fs::read_to_string(path)
        .map(|s| {
            s.lines()
                .filter(|l| !l.is_empty())
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

pub fn write_clean_manifest(path: &Path, entries: &BTreeSet<String>) -> io::Result<()> {
    let mut buf = String::new();
    for e in entries {
        buf.push_str(e);
        buf.push('\n');
    }
    // neet-core の atomic_write を使用 (パーミッション 0o644 でアトミックに同期・書き換え)
    neet_core::atomic::atomic_write(path, buf.as_bytes(), 0o644)
}

pub fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or(OsStr::new("")).to_os_string();
    name.push(suffix);
    path.with_file_name(name)
}
