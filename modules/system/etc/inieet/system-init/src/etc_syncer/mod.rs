mod copy;
mod manifest;
pub mod user_group;

use std::collections::BTreeSet;
use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::path::{Path, PathBuf};

const ETC: &str = "/etc";
const STATIC_LINK: &str = "/etc/static";
const CLEAN_MANIFEST: &str = "/etc/.clean";

pub fn setup_etc(store_etc: &Path, prune: &[PathBuf]) -> io::Result<()> {
    println!("system-init: syncing /etc...");
    atomic_symlink(store_etc, Path::new(STATIC_LINK))?;
    clean_dangling_symlinks(Path::new(ETC), Path::new(STATIC_LINK), prune);

    let previous = manifest::read_clean_manifest(Path::new(CLEAN_MANIFEST));
    let mut created: BTreeSet<String> = BTreeSet::new();

    sync_dir(store_etc, store_etc, Path::new(STATIC_LINK), &mut created);

    for stale in previous.difference(&created) {
        let target = Path::new(ETC).join(stale);
        match fs::remove_file(&target) {
            Ok(()) => eprintln!("system-init: removed obsolete file '{}'", target.display()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => eprintln!(
                "system-init: warning: could not remove stale '{}': {e}",
                target.display()
            ),
        }
    }
    manifest::write_clean_manifest(Path::new(CLEAN_MANIFEST), &created)?;
    Ok(())
}

// ---- /etc への同期 ----

fn sync_dir(root: &Path, dir: &Path, static_link: &Path, created: &mut BTreeSet<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("system-init: warning: cannot read '{}': {e}", dir.display());
            return;
        }
    };

    for entry in entries {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                eprintln!(
                    "system-init: warning: directory entry error in '{}': {e}",
                    dir.display()
                );
                continue;
            }
        };
        sync_entry(root, &entry, static_link, created);
    }
}

/// 1エントリ分の同期処理。ディレクトリなら再帰、ファイルなら install/relink。
fn sync_entry(
    root: &Path,
    entry: &fs::DirEntry,
    static_link: &Path,
    created: &mut BTreeSet<String>,
) {
    let path = entry.path();
    let file_name = entry.file_name();
    let file_name = file_name.to_string_lossy();

    if is_sidecar_file(&file_name) {
        return;
    }

    let Ok(rel) = path.strip_prefix(root) else {
        return;
    };
    let rel = rel.to_string_lossy().into_owned();

    let meta = match fs::symlink_metadata(&path) {
        Ok(m) => m,
        Err(e) => {
            eprintln!(
                "system-init: warning: cannot stat '{}': {e}",
                path.display()
            );
            return;
        }
    };

    if meta.is_dir() {
        sync_dir(root, &path, static_link, created);
        return;
    }

    let target = Path::new(ETC).join(&rel);
    if let Err(e) = ensure_parent_dir(&target) {
        eprintln!(
            "system-init: warning: cannot create '{}': {e}",
            target.display()
        );
        return;
    }

    let mode_file = manifest::with_suffix(&path, ".mode");
    if mode_file.exists() {
        install_managed_file(&path, &target, &mode_file, static_link, &rel, created);
    } else if meta.file_type().is_symlink() {
        relink(&target, &static_link.join(&rel));
    }
}

/// ".mode" ファイルが存在するエントリの実際のインストール処理。
fn install_managed_file(
    src: &Path,
    target: &Path,
    mode_file: &Path,
    static_link: &Path,
    rel: &str,
    created: &mut BTreeSet<String>,
) {
    let mode_str = match fs::read_to_string(mode_file) {
        Ok(s) => s.trim().to_string(),
        Err(e) => {
            eprintln!(
                "system-init: warning: cannot read '{}': {e}",
                mode_file.display()
            );
            return;
        }
    };

    if mode_str == "direct-symlink" {
        link_direct_symlink(target, static_link, rel);
        return;
    }

    match copy::copy_managed_file(src, target, &mode_str) {
        Ok(()) => {
            created.insert(rel.to_string());
        }
        Err(e) => eprintln!(
            "system-init: warning: failed to install '{}': {e}",
            target.display()
        ),
    }
}

fn is_sidecar_file(file_name: &str) -> bool {
    file_name.ends_with(".mode") || file_name.ends_with(".uid") || file_name.ends_with(".gid")
}

fn ensure_parent_dir(target: &Path) -> io::Result<()> {
    match target.parent() {
        Some(parent) => fs::create_dir_all(parent),
        None => Ok(()),
    }
}

fn link_direct_symlink(target: &Path, static_link: &Path, rel: &str) {
    let static_entry = static_link.join(rel);
    let Ok(src_store) = fs::read_link(&static_entry) else {
        return;
    };

    let dst_store = fs::read_link(target).ok();
    if dst_store.as_deref() == Some(src_store.as_path()) {
        return; // すでに正しいリンク先
    }

    let _ = fs::remove_file(target);
    if let Err(e) = symlink(&src_store, target) {
        eprintln!(
            "system-init: warning: failed direct-symlink '{}': {e}",
            target.display()
        );
    }
}

fn relink(link: &Path, target: &Path) {
    if fs::read_link(link).ok().as_deref() == Some(target) {
        return; // すでに同じリンク先
    }
    let _ = fs::remove_file(link);
    if let Err(e) = symlink(target, link) {
        eprintln!(
            "system-init: warning: failed to link '{}': {e}",
            link.display()
        );
    }
}

fn atomic_symlink(target: &Path, link: &Path) -> io::Result<()> {
    let tmp = manifest::with_suffix(link, ".system-init-tmp");
    let _ = fs::remove_file(&tmp);
    symlink(target, &tmp)?;
    fs::rename(&tmp, link)
}

// ---- 不要なシンボリックリンクの掃除 ----

fn clean_dangling_symlinks(dir: &Path, static_link: &Path, prune: &[PathBuf]) {
    let Ok(entries) = fs::read_dir(dir) else {
        return;
    };
    for entry in entries.flatten() {
        clean_entry(&entry, static_link, prune);
    }
}

fn clean_entry(entry: &fs::DirEntry, static_link: &Path, prune: &[PathBuf]) {
    let path = entry.path();
    if prune.iter().any(|p| p == &path) {
        return;
    }

    let Ok(meta) = fs::symlink_metadata(&path) else {
        return;
    };

    if meta.is_dir() {
        clean_dangling_symlinks(&path, static_link, prune);
        return;
    }
    if !meta.file_type().is_symlink() {
        return;
    }

    let Ok(link_target) = fs::read_link(&path) else {
        return;
    };
    if link_target.starts_with(static_link) && !link_target.exists() {
        eprintln!(
            "system-init: removing obsolete symlink '{}'",
            path.display()
        );
        let _ = fs::remove_file(&path);
    }
}
