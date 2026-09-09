use nix::unistd::{chown, Gid, Uid};
use serde::{Deserialize, Serialize};
use std::fs;
use std::io;
use std::os::unix::fs::PermissionsExt;
use std::path::{Path, PathBuf};

#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct WrapperConfig {
    pub program: String,
    pub source: PathBuf,
    #[serde(default)]
    pub setuid: bool,
    #[serde(default)]
    pub setgid: bool,
    #[serde(default = "default_root")]
    pub owner: String,
    #[serde(default = "default_root")]
    pub group: String,
    #[serde(default)]
    pub capabilities: Vec<String>,
}

fn default_root() -> String {
    "root".to_string()
}

pub fn setup_wrappers() -> io::Result<()> {
    let json_path = Path::new("/etc/wrappers.json");
    let wrappers_dir = Path::new("/run/wrappers/bin");

    if !json_path.exists() {
        println!("[wrappers] /etc/wrappers.json not found. Skipping.");
        return Ok(());
    }

    if !wrappers_dir.exists() {
        fs::create_dir_all(wrappers_dir)?;
    }

    let file = fs::File::open(json_path)?;
    let configs: Vec<WrapperConfig> =
        serde_json::from_reader(file).map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    println!("[wrappers] Setting up {} wrapper(s)...", configs.len());

    for config in &configs {
        let target_path = wrappers_dir.join(&config.program);
        let tmp_path = wrappers_dir.join(format!(".{}.tmp", config.program));

        // 1. コピー
        fs::copy(&config.source, &tmp_path)?;

        // 2. まず所有者を root に変更する (重要！)
        let uid = Uid::from_raw(0);
        let gid = Gid::from_raw(0);
        chown(&tmp_path, Some(uid), Some(gid))
            .map_err(|e| io::Error::new(io::ErrorKind::Other, e))?;

        // 3. その後で権限(Setuidビット)を設定する
        let mut mode = 0o755;
        if config.setuid {
            mode |= 0o4000;
        }
        if config.setgid {
            mode |= 0o2000;
        }
        fs::set_permissions(&tmp_path, fs::Permissions::from_mode(mode))?;

        // 4. アトミックに入れ替え
        fs::rename(&tmp_path, target_path)?;
    }

    Ok(())
}
