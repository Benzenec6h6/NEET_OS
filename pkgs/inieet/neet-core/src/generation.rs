use std::{
    fs, io,
    path::{Path, PathBuf},
};

pub const PROFILES: &str = "/nix/var/nix/profiles";
pub const GEN_PREFIX: &str = "neet-gen-";

#[derive(Debug, Clone)]
pub struct Generation {
    pub number: u32,
    pub toplevel: PathBuf,
}

impl Generation {
    pub fn uki_filename(gen_num: u32) -> String {
        format!("{GEN_PREFIX}{gen_num}.efi")
    }

    pub fn kernel_filename(gen_num: u32) -> String {
        format!("{GEN_PREFIX}{gen_num}-vmlinuz")
    }

    pub fn initrd_filename(gen_num: u32) -> String {
        format!("{GEN_PREFIX}{gen_num}-initrd")
    }

    pub fn nvram_label(gen_num: u32) -> String {
        format!("NEET OS (Generation {gen_num})")
    }
}

/// NVRAM ラベル `NEET OS (Generation 12)` から世代番号を取得
pub fn parse_gen_from_label(label: &str) -> Option<u32> {
    let start = label.find("(Generation ")?;
    let rest = &label[start + "(Generation ".len()..];
    let end = rest.find(')')?;
    rest[..end].parse().ok()
}

/// ファイル名 `neet-gen-12.efi` などから世代番号を取得
pub fn parse_gen_from_filename(name: &str) -> Option<u32> {
    let rest = name.strip_prefix(GEN_PREFIX)?;
    let num_str: String = rest.chars().take_while(|c| c.is_ascii_digit()).collect();
    num_str.parse().ok()
}

/// 新しい順。canonicalize 失敗は skipped で返す
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
