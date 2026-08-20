mod copy;
mod manifest;
mod user_group;

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
        let path = entry.path();
        let file_name = entry.file_name();
        let file_name = file_name.to_string_lossy();

        if file_name.ends_with(".mode")
            || file_name.ends_with(".uid")
            || file_name.ends_with(".gid")
        {
            continue;
        }

        let rel = match path.strip_prefix(root) {
            Ok(r) => r.to_string_lossy().into_owned(),
            Err(_) => continue,
        };

        let meta = match fs::symlink_metadata(&path) {
            Ok(m) => m,
            Err(e) => {
                eprintln!(
                    "system-init: warning: cannot stat '{}': {e}",
                    path.display()
                );
                continue;
            }
        };

        if meta.is_dir() {
            sync_dir(root, &path, static_link, created);
            continue;
        }

        let target = Path::new(ETC).join(&rel);
        if let Some(parent) = target.parent() {
            if let Err(e) = fs::create_dir_all(parent) {
                eprintln!(
                    "system-init: warning: cannot create '{}': {e}",
                    parent.display()
                );
                continue;
            }
        }

        let mode_file = manifest::with_suffix(&path, ".mode");

        if mode_file.exists() {
            let mode_str = match fs::read_to_string(&mode_file) {
                Ok(s) => s.trim().to_string(),
                Err(e) => {
                    eprintln!(
                        "system-init: warning: cannot read '{}': {e}",
                        mode_file.display()
                    );
                    continue;
                }
            };

            if mode_str == "direct-symlink" {
                link_direct_symlink(&target, static_link, &rel);
            } else {
                match copy::copy_managed_file(&path, &target, &mode_str) {
                    Ok(()) => {
                        created.insert(rel);
                    }
                    Err(e) => eprintln!(
                        "system-init: warning: failed to install '{}': {e}",
                        target.display()
                    ),
                }
            }
        } else if meta.file_type().is_symlink() {
            relink(&target, &static_link.join(&rel));
        }
    }
}

fn link_direct_symlink(target: &Path, static_link: &Path, rel: &str) {
    let static_entry = static_link.join(rel);
    let src_store = match fs::read_link(&static_entry) {
        Ok(p) => p,
        Err(_) => return,
    };
    let dst_store = fs::read_link(target).ok();
    if dst_store.as_deref() != Some(src_store.as_path()) {
        let _ = fs::remove_file(target);
        if let Err(e) = symlink(&src_store, target) {
            eprintln!(
                "system-init: warning: failed direct-symlink '{}': {e}",
                target.display()
            );
        }
    }
}

fn relink(link: &Path, target: &Path) {
    if let Ok(current) = fs::read_link(link) {
        if current == target {
            return;
        }
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

fn clean_dangling_symlinks(dir: &Path, static_link: &Path, prune: &[PathBuf]) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(_) => return,
    };
    for entry in entries.flatten() {
        let path = entry.path();
        if prune.iter().any(|p| p == &path) {
            continue;
        }
        let meta = match fs::symlink_metadata(&path) {
            Ok(m) => m,
            Err(_) => continue,
        };
        if meta.file_type().is_symlink() {
            if let Ok(link_target) = fs::read_link(&path) {
                if link_target.starts_with(static_link) && !link_target.exists() {
                    eprintln!(
                        "system-init: removing obsolete symlink '{}'",
                        path.display()
                    );
                    let _ = fs::remove_file(&path);
                }
            }
        } else if meta.is_dir() {
            clean_dangling_symlinks(&path, static_link, prune);
        }
    }
}
