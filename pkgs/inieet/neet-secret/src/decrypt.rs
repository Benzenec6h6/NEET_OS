use anyhow::{anyhow, Context, Result};
use nix::unistd::{chown, Gid, Group, Uid, User};
use std::fs::{self, File, Permissions};
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use crate::manifest::{SecretEntry, SecretsManifest};

pub fn run_decrypt(
    manifest_path: &Path,
    identity: &dyn age::Identity,
    runtime_dir: &Path,
) -> Result<()> {
    let manifest_file = File::open(manifest_path)
        .with_context(|| format!("Failed to open manifest: {}", manifest_path.display()))?;
    let manifest: SecretsManifest = serde_json::from_reader(manifest_file)
        .with_context(|| "Failed to parse secrets manifest JSON")?;

    let parent = runtime_dir
        .parent()
        .ok_or_else(|| anyhow!("Invalid runtime_dir"))?;
    let tmp_dir = parent.join("secrets-tmp");
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir)?;
    }
    fs::create_dir_all(&tmp_dir)?;
    fs::set_permissions(&tmp_dir, Permissions::from_mode(0o755))?;

    let by_name_dir = tmp_dir.join("by-name");
    let env_dir = tmp_dir.join("env");
    fs::create_dir_all(&by_name_dir)?;
    fs::create_dir_all(&env_dir)?;

    for secret in &manifest.secrets {
        decrypt_and_deploy_secret(secret, identity, &tmp_dir)?;
    }

    let active_dir = parent.join("secrets-current");
    if active_dir.exists() {
        fs::remove_dir_all(&active_dir)?;
    }
    fs::rename(&tmp_dir, &active_dir)?;
    neet_core::atomic::atomic_symlink(&active_dir, runtime_dir)?;

    println!("neet-secret: successfully decrypted and installed all secrets.");
    Ok(())
}

/// 単一の .age ファイルを復号して標準出力 (stdout) に出力する
pub fn print_secret(file_path: &Path, identity: &dyn age::Identity) -> Result<()> {
    let enc_file = File::open(file_path)
        .with_context(|| format!("Encrypted file not found: {}", file_path.display()))?;

    let decryptor = match age::Decryptor::new(enc_file)
        .map_err(|e| anyhow!("Failed to read age header: {:?}", e))?
    {
        age::Decryptor::Recipients(d) => d,
        age::Decryptor::Passphrase(_) => {
            return Err(anyhow!("Passphrase-protected age files are not supported"));
        }
    };

    let mut reader = decryptor
        .decrypt(std::iter::once(identity))
        .map_err(|e| anyhow!("Failed to decrypt {}: {:?}", file_path.display(), e))?;

    // 標準出力へ直接ストリーム書き出し
    let mut stdout = std::io::stdout().lock();
    std::io::copy(&mut reader, &mut stdout)?;
    stdout.flush()?;

    Ok(())
}

pub fn load_ssh_identity(key_path: &Path) -> Result<Box<dyn age::Identity>> {
    let key_data = fs::read_to_string(key_path)
        .with_context(|| format!("Failed to read SSH key: {}", key_path.display()))?;

    let identity = age::ssh::Identity::from_buffer(
        std::io::Cursor::new(key_data.as_bytes()),
        Some(key_path.to_string_lossy().to_string()),
    )
    .map_err(|e| {
        anyhow!(
            "Failed to parse SSH host key {}: {:?}",
            key_path.display(),
            e
        )
    })?;

    match identity {
        age::ssh::Identity::Unsupported(k) => Err(anyhow!("Unsupported SSH key type: {:?}", k)),
        id => Ok(Box::new(id)),
    }
}

fn decrypt_and_deploy_secret(
    secret: &SecretEntry,
    identity: &dyn age::Identity,
    tmp_root: &Path,
) -> Result<()> {
    let enc_file = File::open(&secret.encrypted_file).with_context(|| {
        format!(
            "Encrypted file not found: {}",
            secret.encrypted_file.display()
        )
    })?;

    let decryptor = match age::Decryptor::new(enc_file)
        .map_err(|e| anyhow!("Failed to read age header: {:?}", e))?
    {
        age::Decryptor::Recipients(d) => d,
        age::Decryptor::Passphrase(_) => {
            return Err(anyhow!(
                "Passphrase-protected age files are not supported for {}",
                secret.name
            ));
        }
    };

    let mut reader = decryptor
        .decrypt(std::iter::once(identity))
        .map_err(|e| anyhow!("Failed to decrypt {}: {:?}", secret.name, e))?;

    let mut decrypted_bytes = Vec::new();
    reader.read_to_end(&mut decrypted_bytes)?;

    let uid = resolve_uid(&secret.owner)?;
    let gid = resolve_gid(&secret.group)?;

    let target_file_path = if let Some(ref custom_path) = secret.path {
        if let Some(parent) = custom_path.parent() {
            fs::create_dir_all(parent)?;
        }
        custom_path.clone()
    } else {
        tmp_root.join("by-name").join(&secret.name)
    };

    write_file_with_perms(&target_file_path, &decrypted_bytes, uid, gid, secret.mode)?;

    if let Some(ref env_cfg) = secret.env {
        let service_env_dir = tmp_root.join("env").join(&env_cfg.service);
        fs::create_dir_all(&service_env_dir)?;
        chown(&service_env_dir, Some(uid), Some(gid))?;
        fs::set_permissions(&service_env_dir, Permissions::from_mode(0o750))?;

        let var_file_path = service_env_dir.join(&env_cfg.var);
        let trimmed_content = trim_single_newline(&decrypted_bytes);
        write_file_with_perms(&var_file_path, trimmed_content, uid, gid, secret.mode)?;
    }

    Ok(())
}

fn write_file_with_perms(path: &Path, data: &[u8], uid: Uid, gid: Gid, mode: u32) -> Result<()> {
    let mut file = File::create(path)
        .with_context(|| format!("Failed to create secret file: {}", path.display()))?;
    file.write_all(data)?;
    file.sync_all()?;

    fs::set_permissions(path, Permissions::from_mode(mode))?;
    chown(path, Some(uid), Some(gid))?;
    Ok(())
}

// Stage 1 でも死なないように "root" の即答＆フォールバックを追加
fn resolve_uid(name: &str) -> Result<Uid> {
    if name == "root" {
        return Ok(Uid::from_raw(0));
    }
    if let Ok(uid_num) = name.parse::<u32>() {
        return Ok(Uid::from_raw(uid_num));
    }
    User::from_name(name)?
        .map(|u| u.uid)
        .ok_or_else(|| anyhow!("User not found: {}", name))
}

// ★ Stage 1 でも死なないように "root" の即答＆フォールバックを追加
fn resolve_gid(name: &str) -> Result<Gid> {
    if name == "root" {
        return Ok(Gid::from_raw(0));
    }
    if let Ok(gid_num) = name.parse::<u32>() {
        return Ok(Gid::from_raw(gid_num));
    }
    Group::from_name(name)?
        .map(|g| g.gid)
        .ok_or_else(|| anyhow!("Group not found: {}", name))
}

fn trim_single_newline(data: &[u8]) -> &[u8] {
    if let Some(stripped) = data.strip_suffix(b"\r\n") {
        stripped
    } else if let Some(stripped) = data.strip_suffix(b"\n") {
        stripped
    } else {
        data
    }
}
