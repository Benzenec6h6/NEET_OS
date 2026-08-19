//! system-init
//!
//! System initialization binary for Nix-based environments.
//! Handles essential filesystem setup, /bin population, /etc syncing, and s6 service setup.

use nix::mount::{mount, MsFlags};
use std::collections::BTreeSet;
use std::env;
use std::ffi::OsStr;
use std::fs;
use std::io;
use std::os::unix::fs::{symlink, PermissionsExt};
use std::path::{Path, PathBuf};
use std::process::Command;

// 定数定義
const ETC: &str = "/etc";
const STATIC_LINK: &str = "/etc/static";
const CLEAN_MANIFEST: &str = "/etc/.clean";
const BIN_DIR: &str = "/bin";
const SERVICE_SRC: &str = "/etc/s6-scan";
const SERVICE_DEST: &str = "/run/service";

fn main() {
    let args: Vec<String> = env::args().collect();
    // 引数を1つ増やして kernel-path を受け取るように想定
    if args.len() < 4 {
        eprintln!(
            "usage: system-init <store-etc-path> <system-path> <kernel-path> [prune-path ...]"
        );
        std::process::exit(1);
    }

    let store_etc = PathBuf::from(&args[1]);
    let system_path = PathBuf::from(&args[2]);
    let kernel_path = PathBuf::from(&args[3]); // 追加
    let prune: Vec<PathBuf> = args[4..].iter().map(PathBuf::from).collect();

    if let Err(e) = run(&store_etc, &system_path, &kernel_path, &prune) {
        eprintln!("system-init: fatal: {e}");
        std::process::exit(1);
    }
}

fn run(
    store_etc: &Path,
    system_path: &Path,
    kernel_path: &Path,
    prune: &[PathBuf],
) -> io::Result<()> {
    setup_essential_fs()?;

    // カーネルモジュールのセットアップを追加
    setup_kernel_modules(kernel_path)?;

    setup_bin(system_path)?;
    setup_etc(store_etc, prune)?;
    setup_s6_services()?;

    Ok(())
}

fn setup_kernel_modules(kernel_path: &Path) -> io::Result<()> {
    println!("system-init: setting up /lib/modules...");

    let lib_dir = Path::new("/lib");
    if !lib_dir.exists() {
        fs::create_dir_all(lib_dir)?;
    }

    let dest = Path::new("/lib/modules");
    let src = kernel_path.join("lib/modules");

    if !src.exists() {
        eprintln!(
            "system-init: warning: kernel modules source not found at {}",
            src.display()
        );
        return Ok(());
    }

    // 既存の /lib/modules がディレクトリでもリンクでも一旦削除する
    if dest.exists() || dest.is_symlink() {
        if dest.is_dir() && !dest.is_symlink() {
            fs::remove_dir_all(dest)?;
        } else {
            fs::remove_file(dest)?;
        }
    }

    // /lib/modules -> /nix/store/...-kernel/lib/modules に直接リンク
    symlink(&src, dest)?;
    println!("system-init: linked /lib/modules to {}", src.display());

    Ok(())
}

/// 必須ファイルシステムのマウント準備
fn setup_essential_fs() -> io::Result<()> {
    let mounts = [
        ("proc", "/proc", "proc"),
        ("sysfs", "/sys", "sysfs"),
        ("devtmpfs", "/dev", "devtmpfs"),
        ("tmpfs", "/run", "tmpfs"),
        ("tmpfs", "/tmp", "tmpfs"),
    ];

    for (source, target, fstype) in mounts {
        // ディレクトリ作成
        fs::create_dir_all(target)?;

        // マウント実行 (すでにマウントされている場合はスキップするなどの処理を入れるとより安全)
        println!("system-init: mounting {} on {}", fstype, target);
        if let Err(e) = mount(
            Some(source),
            target,
            Some(fstype),
            MsFlags::empty(),
            None::<&str>,
        ) {
            // EBUSY (既にマウント済) は許容する
            if e != nix::errno::Errno::EBUSY {
                eprintln!("system-init: warning: failed to mount {}: {}", target, e);
            }
        }
    }

    // マウント後に必要なディレクトリを作成
    fs::create_dir_all("/var/log")?;

    Ok(())
}

/// /bin にシステムパッケージをリンクする
fn setup_bin(system_path: &Path) -> io::Result<()> {
    println!(
        "system-init: populating /bin from {}",
        system_path.display()
    );
    fs::create_dir_all(BIN_DIR)?;

    let store_bin = system_path.join("bin");
    if !store_bin.exists() {
        return Ok(());
    }

    for entry in fs::read_dir(store_bin)? {
        let entry = entry?;
        let file_name = entry.file_name();
        let dest = Path::new(BIN_DIR).join(&file_name);

        // すでに存在する場合は削除して作り直す
        let _ = fs::remove_file(&dest);
        symlink(entry.path(), &dest)?;
    }
    Ok(())
}

/// /etc の同期
fn setup_etc(store_etc: &Path, prune: &[PathBuf]) -> io::Result<()> {
    println!("system-init: syncing /etc...");
    atomic_symlink(store_etc, Path::new(STATIC_LINK))?;
    clean_dangling_symlinks(Path::new(ETC), Path::new(STATIC_LINK), prune);

    let previous = read_clean_manifest(Path::new(CLEAN_MANIFEST));
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
    write_clean_manifest(Path::new(CLEAN_MANIFEST), &created)?;
    Ok(())
}

/// s6-scan ディレクトリを /run/service に準備する
fn setup_s6_services() -> io::Result<()> {
    let src = Path::new(SERVICE_SRC);
    let dest = Path::new(SERVICE_DEST);

    if !src.exists() {
        return Ok(());
    }

    println!("system-init: preparing s6 services in {}", dest.display());
    let _ = fs::remove_dir_all(dest);
    fs::create_dir_all(dest)?;

    for entry in fs::read_dir(src)? {
        let entry = entry?;
        let name = entry.file_name();
        let service_dest = dest.join(name);

        symlink(entry.path(), service_dest)?;
    }
    Ok(())
}

// --- 以下、元の etc-syncer の補助ロジック ---

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

        let mode_file = with_suffix(&path, ".mode");

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
                match copy_managed_file(&path, &target, &mode_str) {
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
            "system-init: warning: could not resolve uid '{}' for '{}', defaulting to 0",
            uid_spec.trim(),
            target.display()
        );
    }
    if gid.is_none() {
        eprintln!(
            "system-init: warning: could not resolve gid '{}' for '{}', defaulting to 0",
            gid_spec.trim(),
            target.display()
        );
    }

    let tmp = with_suffix(target, ".system-init-tmp");
    fs::copy(src, &tmp)?;
    fs::set_permissions(&tmp, fs::Permissions::from_mode(mode))?;
    if let Err(e) = std::os::unix::fs::chown(&tmp, Some(uid.unwrap_or(0)), Some(gid.unwrap_or(0))) {
        let _ = fs::remove_file(&tmp);
        return Err(e);
    }
    fs::rename(&tmp, target)
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
    let tmp = with_suffix(link, ".system-init-tmp");
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

fn resolve_uid(spec: &str) -> Option<u32> {
    match spec.strip_prefix('+') {
        Some(n) => n.parse().ok(),
        None => lookup_passwd_uid(spec),
    }
}

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
        fields.nth(1)?.parse().ok()
    })
}

fn lookup_group_gid(name: &str) -> Option<u32> {
    let contents = fs::read_to_string("/etc/group").ok()?;
    contents.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok()
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

fn with_suffix(path: &Path, suffix: &str) -> PathBuf {
    let mut name = path.file_name().unwrap_or(OsStr::new("")).to_os_string();
    name.push(suffix);
    path.with_file_name(name)
}
