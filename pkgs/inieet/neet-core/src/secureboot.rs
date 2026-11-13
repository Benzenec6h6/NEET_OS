//! neet_core::secureboot
//!
//! Provides cached installation and optional Secure Boot signing for EFI binaries.

use crate::atomic;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

/// 署名用の鍵・証明書ペアを検証し、利用可能なら `Some((key, cert))` を返す。
///
/// * `(Some(k), Some(c))` で両方実在する → `Some((k, c))`
/// * `(Some(k), Some(c))` で片方または両方存在しない → 警告を出して `None`
/// * 片方だけ `Some` → 警告を出して `None`
/// * `(None, None)` → 意図的な署名無効とみなし、警告なしで `None`
pub fn resolve_signing_pair<'a>(
    key: Option<&'a Path>,
    cert: Option<&'a Path>,
    log_tag: Option<&str>,
) -> Option<(&'a Path, &'a Path)> {
    let tag_prefix = log_tag.map(|t| format!("{t}: ")).unwrap_or_default();

    match (key, cert) {
        (Some(k), Some(c)) if k.exists() && c.exists() => Some((k, c)),
        (Some(k), Some(c)) => {
            eprintln!(
                "{tag_prefix}[WARNING] Secure Boot key/cert not found (key: {}, cert: {}); falling back to unsigned.",
                k.display(),
                c.display()
            );
            None
        }
        (Some(_), None) | (None, Some(_)) => {
            eprintln!(
                "{tag_prefix}[WARNING] Incomplete Secure Boot key/cert pair; falling back to unsigned."
            );
            None
        }
        (None, None) => None,
    }
}

/// EFI バイナリをキャッシュ検証付きでインストール＆署名する。
///
/// * ソースバイナリのハッシュ
/// * 証明書のハッシュ（署名有効時）または "unsigned"
///
/// の両方を検証し、差異がある場合のみコピーおよび `sbsign` を実行する。
/// 戻り値: 更新（署名またはコピー）が行われた場合は `true`、キャッシュ一致でスキップされた場合は `false`
pub fn install_and_sign_efi_cached(
    src: &Path,
    dest: &Path,
    key: Option<&Path>,
    cert: Option<&Path>,
    log_tag: Option<&str>,
) -> io::Result<bool> {
    if !src.exists() {
        return Err(io::Error::new(
            io::ErrorKind::NotFound,
            format!("source EFI binary not found: {}", src.display()),
        ));
    }

    // 宛先ディレクトリを担保
    if let Some(parent) = dest.parent() {
        fs::create_dir_all(parent)?;
    }

    let file_name = dest
        .file_name()
        .ok_or_else(|| io::Error::new(io::ErrorKind::InvalidInput, "invalid destination path"))?
        .to_string_lossy();
    let hash_file = dest.with_file_name(format!("{file_name}.hash"));

    // 1. ソースバイナリのハッシュ計算
    let src_hash = hex_encode(&atomic::sha256_file(src)?);

    // 2. 署名トークンの決定
    let signing_pair = resolve_signing_pair(key, cert, log_tag);

    let sign_token = if let Some((_, cert_path)) = signing_pair {
        let cert_hash = hex_encode(&atomic::sha256_file(cert_path)?);
        format!("signed:{cert_hash}")
    } else {
        "unsigned".to_string()
    };

    let expected_cache = format!("{src_hash} {sign_token}");

    // 3. キャッシュ一致ならスキップ
    if dest.exists() && hash_file.exists() {
        if let Ok(cached) = fs::read_to_string(&hash_file) {
            if cached.trim() == expected_cache {
                return Ok(false); // 最新のためスキップ
            }
        }
    }

    // ログ用の接頭辞
    let tag_prefix = log_tag.map(|t| format!("{t}: ")).unwrap_or_default();

    // 4. 配置または署名の実行
    if let Some((k, c)) = signing_pair {
        println!(
            "{tag_prefix}signing and installing {} (cert: {})",
            dest.display(),
            c.display()
        );

        let tmp = atomic::tmp_sibling(dest);
        let _ = fs::remove_file(&tmp);

        let status = Command::new("sbsign")
            .arg("--key")
            .arg(k)
            .arg("--cert")
            .arg(c)
            .arg("--output")
            .arg(&tmp)
            .arg(src)
            .status();

        let status = match status {
            Ok(s) => s,
            Err(e) => {
                let _ = fs::remove_file(&tmp);
                return Err(io::Error::new(
                    io::ErrorKind::Other,
                    format!("failed to execute sbsign: {e}. Is 'sbsigntool' installed?"),
                ));
            }
        };

        if !status.success() {
            let _ = fs::remove_file(&tmp);
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("sbsign failed for {}", src.display()),
            ));
        }

        if let Err(e) = fs::rename(&tmp, dest) {
            let _ = fs::remove_file(&tmp);
            return Err(e);
        }
        atomic::sync_parent(dest)?;
    } else {
        println!("{tag_prefix}installing unsigned {}", dest.display());
        atomic::atomic_copy_if_changed(src, dest, 0o755)?;
    }

    // 5. 複合キャッシュの書き込み
    atomic::atomic_write(&hash_file, expected_cache.as_bytes(), 0o644)?;
    Ok(true)
}

fn hex_encode(bytes: &[u8; 32]) -> String {
    let mut s = String::with_capacity(64);
    for b in bytes {
        use std::fmt::Write;
        let _ = write!(s, "{:02x}", b);
    }
    s
}
