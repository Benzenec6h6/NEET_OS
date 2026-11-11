use anyhow::Result;
use colored::*;
use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize, PartialEq, Eq, Hash)]
pub struct StateDir {
    pub path: String,
    pub mode: String,
    pub user: String,
    pub group: String,
}

pub fn diff_state_directories(old_etc: &Path, new_etc: &Path) -> Result<bool> {
    println!("{}", "[Impermanence & State Directories]".bold());

    let old_dirs: HashSet<StateDir> = read_json_or_empty(&old_etc.join("state-directories.json"));
    let new_dirs: HashSet<StateDir> = read_json_or_empty(&new_etc.join("state-directories.json"));

    let mut has_diff = false;

    // 追加
    for dir in new_dirs.difference(&old_dirs) {
        has_diff = true;
        println!(
            "  {} {} (mode: {}, {}:{})",
            "[+]".green().bold(),
            dir.path,
            dir.mode,
            dir.user,
            dir.group
        );
    }

    // 削除（警告）
    for dir in old_dirs.difference(&new_dirs) {
        has_diff = true;
        if dir.path.starts_with("/persist") {
            println!(
                "  {} {} unpersisted! Will be WIPED on next boot!",
                "[!] WARNING:".red().bold(),
                dir.path.yellow().bold()
            );
        } else {
            println!("  {} {}", "[-]".red().bold(), dir.path);
        }
    }

    if !has_diff {
        println!("  (no changes)");
    }
    Ok(has_diff)
}

fn read_json_or_empty<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> T {
    fs::read_to_string(path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}
