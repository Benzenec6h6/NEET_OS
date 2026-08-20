use super::manifest::with_suffix;
use super::user_group::{resolve_gid, resolve_uid};
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

pub fn copy_managed_file(src: &Path, target: &Path, mode_str: &str) -> io::Result<()> {
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
