//! Garbage Collection utilities for NEET OS (ESP files & NVRAM entries)

use crate::{generation, uefi};
use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// 指定したディレクトリ内のファイルのうち、
/// 「neet-gen- プレフィックスを持ち、有効な世代セットに含まれないファイル」を削除する
pub fn cleanup_stale_generation_files(
    dir: &Path,
    active_gen_numbers: &HashSet<u32>,
) -> io::Result<Vec<PathBuf>> {
    if !dir.exists() {
        return Ok(Vec::new());
    }

    let mut removed = Vec::new();
    for entry in fs::read_dir(dir)? {
        let entry = entry?;
        let name = entry.file_name().to_string_lossy().into_owned();

        // 世代番号をパースできるかチェック
        if let Some(gen_num) = generation::parse_gen_from_filename(&name) {
            if !active_gen_numbers.contains(&gen_num) {
                fs::remove_file(entry.path())?;
                removed.push(entry.path());
            }
        }
    }
    Ok(removed)
}

/// NVRAM 内の古い NEET OS エントリ（有効な世代セットに含まれないもの）を削除する
pub fn cleanup_stale_nvram_entries(
    active_gen_numbers: &HashSet<u32>,
) -> io::Result<Vec<(String, String)>> {
    let existing_entries = uefi::list_boot_entries()?;
    let mut removed = Vec::new();

    for (label, boot_num) in existing_entries {
        if let Some(gen_num) = generation::parse_gen_from_label(&label) {
            if !active_gen_numbers.contains(&gen_num) {
                uefi::delete_boot_entry(&boot_num)?;
                removed.push((label, boot_num));
            }
        }
    }
    Ok(removed)
}
