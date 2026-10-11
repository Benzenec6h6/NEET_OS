use std::{
    fs, io,
    path::{Path, PathBuf},
};

pub const PROFILES: &str = "/nix/var/nix/profiles";

#[derive(Debug, Clone)]
pub struct Generation {
    pub number: u32,
    pub toplevel: PathBuf, // canonicalize 済み
}

/// 新しい順。canonicalize 失敗 (リンク先が GC 済み) は黙って捨てず、skipped で返す。
pub fn list(profiles: &Path) -> io::Result<(Vec<Generation>, Vec<(u32, io::Error)>)> {
    let mut gens = Vec::new();
    let mut skipped = Vec::new();
    for entry in fs::read_dir(profiles)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();
        let Some(num) = name
            .strip_prefix("system-")
            .and_then(|s| s.strip_suffix("-link"))
            .and_then(|s| s.parse::<u32>().ok())
        else {
            continue;
        };
        match fs::canonicalize(entry.path()) {
            Ok(p) => gens.push(Generation {
                number: num,
                toplevel: p,
            }),
            Err(e) => skipped.push((num, e)),
        }
    }
    gens.sort_by(|a, b| b.number.cmp(&a.number));
    Ok((gens, skipped))
}
