//! etc-syncer
//!
//! Rust port of finix's `setup-etc.sh` (which itself is a POSIX-sh port of
//! NixOS's `setup-etc.pl`). Same algorithm, different runtime:
//!
//!   1. Atomically repoint `/etc/static` at this generation's store `etc/`.
//!   2. Sweep `/etc` for symlinks that point through `/etc/static/...` but
//!      whose target no longer exists there (previous generation's debris).
//!   3. Walk the store `etc/` tree. For every entry:
//!        - a plain symlink source        -> `/etc/<rel>` -> `/etc/static/<rel>`
//!        - a `.mode` sidecar of "direct-symlink" -> `/etc/<rel>` linked
//!          straight at the resolved store path (bypassing `/etc/static`)
//!        - any other `.mode` sidecar      -> copy the file, chown/chmod it
//!   4. Copied (not symlinked) files are tracked in `/etc/.clean` across
//!      generations, since "does the symlink still resolve" can't tell us
//!      whether a *copied* file is stale. Files copied last time but not
//!      recreated this time are deleted.
//!
//! Deliberately does not bail out on the first error: one bad entry
//! shouldn't take down the whole `/etc` rebuild during boot.
//!
//! Usage: etc-syncer <store-etc-path> [prune-path ...]
//!   store-etc-path  Nix store path containing the etc/ tree to sync from.
//!   prune-path      Absolute /etc paths to skip entirely during the
//!                   dangling-symlink sweep (e.g. a hand-maintained dir).

use std::collections::BTreeSet;
use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::os::unix::fs::symlink;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

const ETC: &str = "/etc";
const STATIC_LINK: &str = "/etc/static";
const CLEAN_MANIFEST: &str = "/etc/.clean";

fn main() {
    let args: Vec<String> = env::args().collect();
    let store_etc = match args.get(1) {
        Some(p) => PathBuf::from(p),
        None => {
            eprintln!("usage: etc-syncer <store-etc-path> [prune-path ...]");
            std::process::exit(1);
        }
    };
    let prune: Vec<PathBuf> = args[2..].iter().map(PathBuf::from).collect();

    if let Err(e) = run(&store_etc, &prune) {
        eprintln!("etc-syncer: fatal: {e}");
        std::process::exit(1);
    }
}

fn run(store_etc: &Path, prune: &[PathBuf]) -> io::Result<()> {
    // specialfs activation (mounting /tmp etc.) may not have run yet.
    fs::create_dir_all("/tmp")?;

    // 1. Atomically repoint /etc/static at the new generation's etc tree.
    atomic_symlink(store_etc, Path::new(STATIC_LINK))?;

    // 2. Remove symlinks under /etc that point into /etc/static but whose
    //    target no longer exists there (leftovers from the prior generation).
    clean_dangling_symlinks(Path::new(ETC), Path::new(STATIC_LINK), prune);

    // 3. Load the manifest of files that were *copied* (not symlinked) last run.
    let previous = read_clean_manifest(Path::new(CLEAN_MANIFEST));
    let mut created: BTreeSet<String> = BTreeSet::new();

    // 4. Walk the store's etc tree and materialize each entry under /etc.
    sync_dir(store_etc, store_etc, Path::new(STATIC_LINK), &mut created);

    // 5. Delete copied files that existed before but weren't recreated this run.
    for stale in previous.difference(&created) {
        let target = Path::new(ETC).join(stale);
        match fs::remove_file(&target) {
            Ok(()) => eprintln!("etc-syncer: removed obsolete file '{}'", target.display()),
            Err(e) if e.kind() == io::ErrorKind::NotFound => {}
            Err(e) => eprintln!(
                "etc-syncer: warning: could not remove stale '{}': {e}",
                target.display()
            ),
        }
    }

    // 6. Persist the new manifest for next time.
    write_clean_manifest(Path::new(CLEAN_MANIFEST), &created)?;

    Ok(())
}

/// Recursively mirror `dir` (a subtree of `root`) into `/etc`.
fn sync_dir(root: &Path, dir: &Path, static_link: &Path, created: &mut BTreeSet<String>) {
    let entries = match fs::read_dir(dir) {
        Ok(e) => e,
        Err(e) => {
            eprintln!("etc-syncer: warning: cannot read '{}': {e}", dir.display());
            return;
        }
    };

    for entry in entries {
        let entry = match entry {
            Ok(e) => e,
            Err(e) => {
                eprintln!(
                    "etc-syncer: warning: directory entry error in '{}': {e}",
                    dir.display()
                );
                continue;
            }
        };
        let path = entry.path();
        let file_name = entry.file_name();
        let file_name = file_name.to_string_lossy();

        // Sidecar metadata files are consumed alongside their owning entry;
        // they are never visited as entries in their own right.
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
                eprintln!("etc-syncer: warning: cannot stat '{}': {e}", path.display());
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
                    "etc-syncer: warning: cannot create '{}': {e}",
                    parent.display()
                );
                continue;
            }
        }

        let mode_file = with_suffix(&path, ".mode");

        if mode_file.exists() {
            let mode_str = match fs::read_to_string(&mode_file) {
                Ok(s) => s.trim().to_string(),
                Err(e) => {
                    eprintln!(
                        "etc-syncer: warning: cannot read '{}': {e}",
                        mode_file.display()
                    );
                    continue;
                }
            };

            if mode_str == "direct-symlink" {
                link_direct_symlink(&target, static_link, &rel);
            } else {
                match copy_managed_file(&path, &target, &mode_str) {
                    Ok(()) => {
                        created.insert(rel);
                    }
                    Err(e) => eprintln!(
                        "etc-syncer: warning: failed to install '{}': {e}",
                        target.display()
                    ),
                }
            }
        } else if meta.file_type().is_symlink() {
            // Unmoded symlink source: point /etc/<rel> at /etc/static/<rel>
            // rather than resolving it now, so it tracks future generations.
            relink(&target, &static_link.join(&rel));
        }
        // Entries that are neither symlinks nor carry a .mode sidecar are
        // ignored, matching setup-etc.sh.
    }
}

/// Copy `src` to `target` with the permissions/ownership from its sidecar
/// files, via a temp file + rename so `target` is never briefly missing.
fn copy_managed_file(src: &Path, target: &Path, mode_str: &str) -> io::Result<()> {
    let mode = u32::from_str_radix(mode_str, 8).map_err(|_| {
        io::Error::new(
            io::ErrorKind::InvalidData,
            format!("invalid mode '{mode_str}'"),
        )
    })?;

    let uid_spec = fs::read_to_string(with_suffix(src, ".uid")).unwrap_or_else(|_| "+0".into());
    let gid_spec = fs::read_to_string(with_suffix(src, ".gid")).unwrap_or_else(|_| "+0".into());
    let uid = resolve_uid(uid_spec.trim());
    let gid = resolve_gid(gid_spec.trim());
    if uid.is_none() {
        eprintln!(
            "etc-syncer: warning: could not resolve uid '{}' for '{}', defaulting to 0",
            uid_spec.trim(),
            target.display()
        );
    }
    if gid.is_none() {
        eprintln!(
            "etc-syncer: warning: could not resolve gid '{}' for '{}', defaulting to 0",
            gid_spec.trim(),
            target.display()
        );
    }

    let tmp = with_suffix(target, ".etc-syncer-tmp");
    fs::copy(src, &tmp)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
    if let Err(e) = std::os::unix::fs::chown(&tmp, Some(uid.unwrap_or(0)), Some(gid.unwrap_or(0))) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::rename(&tmp, target)
}

/// Link `/etc/<rel>` directly at the real store path behind
/// `/etc/static/<rel>`, bypassing the `/etc/static` indirection.
fn link_direct_symlink(target: &Path, static_link: &Path, rel: &str) {
    let static_entry = static_link.join(rel);
    let src_store = match fs::read_link(&static_entry) {
        Ok(p) => p,
        Err(_) => return, // not a symlink in the store tree; nothing to resolve
    };
    let dst_store = fs::read_link(target).ok();
    if dst_store.as_deref() != Some(src_store.as_path()) {
        let _ = fs::remove_file(target);
        if let Err(e) = symlink(&src_store, target) {
            eprintln!(
                "etc-syncer: warning: failed direct-symlink '{}': {e}",
                target.display()
            );
        }
    }
}

/// `ln -sfn target link`, but a no-op if `link` already points at `target`.
fn relink(link: &Path, target: &Path) {
    if let Ok(current) = fs::read_link(link) {
        if current == target {
            return;
        }
    }
    let _ = fs::remove_file(link);
    if let Err(e) = symlink(target, link) {
        eprintln!(
            "etc-syncer: warning: failed to link '{}': {e}",
            link.display()
        );
    }
}

/// `ln -sfn target link`, but via a temp symlink + rename so `link` is
/// never briefly missing (used for /etc/static itself).
fn atomic_symlink(target: &Path, link: &Path) -> io::Result<()> {
    let tmp = with_suffix(link, ".etc-syncer-tmp");
    let _ = fs::remove_file(&tmp);
    symlink(target, &tmp)?;
    fs::rename(&tmp, link)
}

/// Recursively remove symlinks under `dir` that point through `static_link`
/// but whose target no longer exists (previous generation's debris).
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
                    eprintln!("etc-syncer: removing obsolete symlink '{}'", path.display());
                    let _ = fs::remove_file(&path);
                }
            }
        } else if meta.is_dir() {
            clean_dangling_symlinks(&path, static_link, prune);
        }
    }
}

/// Resolve a uid spec: "+123" is a literal uid, anything else is a
/// username looked up in /etc/passwd.
fn resolve_uid(spec: &str) -> Option<u32> {
    match spec.strip_prefix('+') {
        Some(n) => n.parse().ok(),
        None => lookup_passwd_uid(spec),
    }
}

/// Resolve a gid spec: "+123" is a literal gid, anything else is a
/// group name looked up in /etc/group.
fn resolve_gid(spec: &str) -> Option<u32> {
    match spec.strip_prefix('+') {
        Some(n) => n.parse().ok(),
        None => lookup_group_gid(spec),
    }
}

fn lookup_passwd_uid(name: &str) -> Option<u32> {
    let contents = fs::read_to_string("/etc/passwd").ok()?;
    contents.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok() // skip the password field, take uid
    })
}

fn lookup_group_gid(name: &str) -> Option<u32> {
    let contents = fs::read_to_string("/etc/group").ok()?;
    contents.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok() // skip the password field, take gid
    })
}

fn read_clean_manifest(path: &Path) -> BTreeSet<String> {
    fs::read_to_string(path)
        .map(|s| {
            s.lines()
                .filter(|l| !l.is_empty())
                .map(String::from)
                .collect()
        })
        .unwrap_or_default()
}

fn write_clean_manifest(path: &Path, entries: &BTreeSet<String>) -> io::Result<()> {
    let mut buf = String::new();
    for e in entries {
        buf.push_str(e);
        buf.push('\n');
    }
    let tmp = with_suffix(path, ".tmp");
    fs::write(&tmp, buf)?;
    fs::rename(&tmp, path)
}

/// Append `suffix` to `path`'s file name (e.g. "foo" -> "foo.mode"),
/// preserving the parent directory.
fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or(OsStr::new("")).to_os_string();
    name.push(suffix);
    path.with_file_name(name)
}
