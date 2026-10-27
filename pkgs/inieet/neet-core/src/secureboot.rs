//! neet_core::secureboot
//!
//! Provides cached installation and optional Secure Boot signing for EFI binaries.

use crate::atomic;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

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
    let is_signing_enabled = match (key, cert) {
        (Some(k), Some(c)) => k.exists() && c.exists(),
        _ => false,
    };

    let sign_token = if is_signing_enabled {
        let cert_path = cert.unwrap();
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
    if is_signing_enabled {
        let k = key.unwrap();
        let c = cert.unwrap();
        println!(
            "{tag_prefix}signing and installing {} (cert: {})",
            dest.display(),
            c.display()
        );

        let status = Command::new("sbsign")
            .arg("--key")
            .arg(k)
            .arg("--cert")
            .arg(c)
            .arg("--output")
            .arg(dest)
            .arg(src)
            .status()
            .map_err(|e| {
                io::Error::new(
                    io::ErrorKind::Other,
                    format!("failed to execute sbsign: {e}. Is 'sbsigntool' installed?"),
                )
            })?;

        if !status.success() {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("sbsign failed for {}", src.display()),
            ));
        }
    } else {
        println!("{tag_prefix}installing un-signed {}", dest.display());
        atomic::atomic_copy_if_changed(src, dest, 0o755)?;
    }

    // 5. 複合キャッシュの書き込み
    fs::write(&hash_file, expected_cache)?;
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
