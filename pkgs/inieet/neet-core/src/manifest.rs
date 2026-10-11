use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

pub const SCHEMA: u32 = 1;

#[derive(Debug, Clone, Serialize, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub schema: u32,
    pub etc: PathBuf,
    pub system_path: PathBuf,
    pub kernel: PathBuf,
    pub modules: PathBuf, // /lib/modules の元
    pub firmware: PathBuf,
    pub stage2: PathBuf,
    pub s6rc_compiled: PathBuf,
    pub graphics_drivers: Option<PathBuf>,
    pub graphics_drivers_32: Option<PathBuf>,
    /// 再起動でしか反映できないものの識別子 (kernel, initrd, modules, firmware, cmdline...)
    pub boot_fingerprint: String,
}

/// 読み込んだ toplevel と、その manifest を一組で持つ。
#[derive(Debug, Clone)]
pub struct Toplevel {
    pub path: PathBuf,
    pub manifest: Manifest,
}

impl Toplevel {
    pub fn load(path: &Path) -> io::Result<Self> {
        let path = fs::canonicalize(path)?;
        let text = fs::read_to_string(path.join("neet.json"))?;
        let manifest: Manifest = serde_json::from_str(&text)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        if manifest.schema != SCHEMA {
            return Err(io::Error::new(
                io::ErrorKind::InvalidData,
                format!(
                    "unsupported manifest schema {} (expected {SCHEMA})",
                    manifest.schema
                ),
            ));
        }
        let t = Toplevel { path, manifest };
        t.validate()?;
        Ok(t)
    }

    /// 必須パスがすべて実在すること。prepare 段階で呼べば、commit 前に失敗を出せる。
    pub fn validate(&self) -> io::Result<()> {
        let m = &self.manifest;
        for (name, p) in [
            ("etc", &m.etc),
            ("systemPath", &m.system_path),
            ("kernel", &m.kernel),
            ("modules", &m.modules),
            ("firmware", &m.firmware),
            ("stage2", &m.stage2),
            ("s6rcCompiled", &m.s6rc_compiled),
        ] {
            if !p.exists() {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("manifest.{name} not found: {}", p.display()),
                ));
            }
        }
        Ok(())
    }
}

/// 稼働中の世代 (/run/current-system) と、ブート時の世代 (/run/booted-system)
pub fn current() -> io::Result<Toplevel> {
    Toplevel::load(Path::new("/run/current-system"))
}
pub fn booted() -> io::Result<Toplevel> {
    Toplevel::load(Path::new("/run/booted-system"))
}
