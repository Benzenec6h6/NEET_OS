use anyhow::Result;
use colored::*;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

pub fn diff_packages(old_sys_path: &Path, new_sys_path: &Path) -> Result<bool> {
    println!("{}", "[Packages (/bin)]".bold());

    let old_bins = scan_bin_targets(&old_sys_path.join("bin"));
    let new_bins = scan_bin_targets(&new_sys_path.join("bin"));

    let old_keys: HashSet<_> = old_bins.keys().collect();
    let new_keys: HashSet<_> = new_bins.keys().collect();
    let mut has_diff = false;

    for name in new_keys.difference(&old_keys) {
        has_diff = true;
        let target = &new_bins[*name];
        println!("  {} {} -> {}", "[+]".green().bold(), name, target);
    }

    for name in old_keys.difference(&new_keys) {
        has_diff = true;
        println!("  {} {}", "[-]".red().bold(), name);
    }

    for name in old_keys.intersection(&new_keys) {
        let old_target = &old_bins[*name];
        let new_target = &new_bins[*name];
        if old_target != new_target {
            has_diff = true;
            println!(
                "  {} {} ({} -> {})",
                "[~]".yellow().bold(),
                name,
                old_target,
                new_target
            );
        }
    }

    if !has_diff {
        println!("  (no changes)");
    }
    Ok(has_diff)
}

fn scan_bin_targets(bin_dir: &Path) -> HashMap<String, String> {
    let mut map = HashMap::new();
    let Ok(entries) = fs::read_dir(bin_dir) else {
        return map;
    };

    for entry in entries.flatten() {
        let path = entry.path();
        if let Ok(target) = fs::read_link(&path) {
            // 例: /nix/store/...-ripgrep-14.1.0/bin/rg からパッケージ名部分を抽出
            let pkg_name =
                extract_pkg_name(&target).unwrap_or_else(|| target.display().to_string());
            map.insert(entry.file_name().to_string_lossy().into_owned(), pkg_name);
        }
    }
    map
}

fn extract_pkg_name(store_path: &Path) -> Option<String> {
    for ancestor in store_path.ancestors() {
        if let Some(parent) = ancestor.parent() {
            if parent == Path::new("/nix/store") {
                let s = ancestor.file_name()?.to_str()?;
                // 32文字のハッシュ + ハイフンをスキップ
                if s.len() > 33 && s.chars().nth(32) == Some('-') {
                    return Some(s[33..].to_string());
                }
                return Some(s.to_string());
            }
        }
    }
    None
}
