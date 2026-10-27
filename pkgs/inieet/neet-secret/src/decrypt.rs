use anyhow::{anyhow, Context, Result};
use nix::unistd::{chown, Gid, Group, Uid, User};
use std::fs::{self, File, Permissions};
use std::io::{Read, Write};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;

use crate::manifest::{SecretEntry, SecretsManifest};

pub fn run_decrypt(
    manifest_path: &Path,
    key_path: &Path,
    runtime_dir: &Path, // 例: /run/secrets
) -> Result<()> {
    // 1. マニフェストの読み込み
    let manifest_file = File::open(manifest_path)
        .with_context(|| format!("Failed to open manifest: {}", manifest_path.display()))?;
    let manifest: SecretsManifest = serde_json::from_reader(manifest_file)
        .with_context(|| "Failed to parse secrets manifest JSON")?;

    // 2. SSH 秘密鍵のパース
    let identity = load_ssh_identity(key_path)?;

    // 3. 作業用一時ディレクトリを作成 (/run/secrets-tmp)
    // tmpfs 上で作業し、最後にアトミックに差し替える
    let parent = runtime_dir
        .parent()
        .ok_or_else(|| anyhow!("Invalid runtime_dir"))?;
    let tmp_dir = parent.join("secrets-tmp");
    if tmp_dir.exists() {
        fs::remove_dir_all(&tmp_dir)?;
    }
    fs::create_dir_all(&tmp_dir)?;
    fs::set_permissions(&tmp_dir, Permissions::from_mode(0o755))?;

    // ディレクトリ骨格の準備
    let by_name_dir = tmp_dir.join("by-name");
    let env_dir = tmp_dir.join("env");
    fs::create_dir_all(&by_name_dir)?;
    fs::create_dir_all(&env_dir)?;

    // 4. 各シークレットの復号と配置
    for secret in &manifest.secrets {
        decrypt_and_deploy_secret(secret, &identity, &tmp_dir)?;
    }

    // 5. アトミックな切り替え (symlink または rename)
    // /run/secrets を current へのシンボリックリンクにする方式
    // 例: /run/secrets-gen-XYZ を作成し、/run/secrets をリンク
    let active_dir = parent.join("secrets-current");
    if active_dir.exists() {
        fs::remove_dir_all(&active_dir)?;
    }
    fs::rename(&tmp_dir, &active_dir)?;

    // neet_core::atomic::atomic_symlink を利用して /run/secrets を張り替え
    neet_core::atomic::atomic_symlink(&active_dir, runtime_dir)?;

    println!("neet-secret: successfully decrypted and installed all secrets.");
    Ok(())
}

fn load_ssh_identity(key_path: &Path) -> Result<Box<dyn age::Identity>> {
    let key_data = fs::read_to_string(key_path)
        .with_context(|| format!("Failed to read SSH key: {}", key_path.display()))?;

    // age::ssh::Identity は SSH の ed25519 や RSA 秘密鍵をパースできる
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
    identity: &Box<dyn age::Identity>,
    tmp_root: &Path,
) -> Result<()> {
    // age ファイルを開いて復号
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
        .decrypt(std::iter::once(identity.as_ref()))
        .map_err(|e| anyhow!("Failed to decrypt {}: {:?}", secret.name, e))?;

    let mut decrypted_bytes = Vec::new();
    reader.read_to_end(&mut decrypted_bytes)?;

    // ユーザー・グループIDの解決
    let uid = resolve_uid(&secret.owner)?;
    let gid = resolve_gid(&secret.group)?;

    // A. 通常ファイルとしての配置 (by-name or カスタムパス)
    let target_file_path = if let Some(ref custom_path) = secret.path {
        // カスタムパス指定の場合はその絶対パスに直接書き出す準備
        // （tmp_root 配下ではなく直接指定の場合はディレクトリ作成に注意）
        if let Some(parent) = custom_path.parent() {
            fs::create_dir_all(parent)?;
        }
        custom_path.clone()
    } else {
        tmp_root.join("by-name").join(&secret.name)
    };

    write_file_with_perms(&target_file_path, &decrypted_bytes, uid, gid, secret.mode)?;

    // B. s6-envdir 向けの配置 (/run/secrets/env/<service>/<VAR>)
    if let Some(ref env_cfg) = secret.env {
        let service_env_dir = tmp_root.join("env").join(&env_cfg.service);
        fs::create_dir_all(&service_env_dir)?;
        // envdir ディレクトリ自体の所有権もサービスユーザーに合わせる
        chown(&service_env_dir, Some(uid), Some(gid))?;
        fs::set_permissions(&service_env_dir, Permissions::from_mode(0o750))?;

        let var_file_path = service_env_dir.join(&env_cfg.var);

        // s6-envdir はファイルの改行も値として含む場合があるため、
        // 末尾の1つの改行 (\n または \r\n) はトリムするのが通例
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

fn resolve_uid(name: &str) -> Result<Uid> {
    if let Ok(uid_num) = name.parse::<u32>() {
        return Ok(Uid::from_raw(uid_num));
    }
    User::from_name(name)?
        .map(|u| u.uid)
        .ok_or_else(|| anyhow!("User not found: {}", name))
}

fn resolve_gid(name: &str) -> Result<Gid> {
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
