use serde::{Deserialize, Serialize};
use std::{
    fs, io,
    path::{Path, PathBuf},
};

pub const SCHEMA: u32 = 1;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub schema: u32,
    pub kernel_params: Vec<String>,
    pub boot_fingerprint: String,
}

pub struct Core {
    pub path: PathBuf,
    pub manifest: Manifest,
}

impl Core {
    pub fn load(path: &Path) -> io::Result<Self> { /* canonicalize, neet.json を読み schema 検査 */
    }
    pub fn etc(&self) -> PathBuf {
        self.path.join("etc")
    }
    pub fn system_path(&self) -> PathBuf {
        self.path.join("system-path")
    }
    pub fn modules(&self) -> PathBuf {
        self.path.join("modules")
    }
    pub fn firmware(&self) -> PathBuf {
        self.path.join("firmware")
    }
    pub fn s6_rc(&self) -> Option<PathBuf> {
        self.opt("s6-rc")
    }
    pub fn graphics_drivers(&self) -> Option<PathBuf> {
        self.opt("graphics-drivers")
    }
    fn opt(&self, n: &str) -> Option<PathBuf> {
        let p = self.path.join(n);
        p.symlink_metadata().is_ok().then_some(p)
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
