use serde::Deserialize;
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

pub const SCHEMA: u32 = 1;

#[derive(Debug, Clone, Deserialize)]
#[serde(rename_all = "camelCase")]
pub struct Manifest {
    pub schema: u32,
    pub kernel_params: Vec<String>,
    pub boot_fingerprint: String,
}

#[derive(Debug, Clone)]
pub struct Core {
    pub path: PathBuf,
    pub manifest: Manifest,
}

// 以前のコードとの互換用エイリアス
pub type Toplevel = Core;

impl Core {
    pub fn load(path: &Path) -> io::Result<Self> {
        let canonical = fs::canonicalize(path)?;

        // 指定されたパス直下、または toplevel/core 直下のどちらに neet.json があっても対応
        let core_path = if canonical.join("neet.json").exists() {
            canonical
        } else if canonical.join("core/neet.json").exists() {
            canonical.join("core")
        } else {
            return Err(io::Error::new(
                io::ErrorKind::NotFound,
                format!(
                    "neet.json not found in {} or {}/core",
                    canonical.display(),
                    canonical.display()
                ),
            ));
        };

        let text = fs::read_to_string(core_path.join("neet.json"))?;
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

        let core = Core {
            path: core_path,
            manifest,
        };
        core.validate()?;
        Ok(core)
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

    pub fn graphics_drivers_32(&self) -> Option<PathBuf> {
        self.opt("graphics-drivers-32bit")
    }

    fn opt(&self, n: &str) -> Option<PathBuf> {
        let p = self.path.join(n);
        p.symlink_metadata().is_ok().then_some(p)
    }

    /// 必須リンク (etc, system-path, modules, firmware) の実在検査
    pub fn validate(&self) -> io::Result<()> {
        for (name, p) in [
            ("etc", self.etc()),
            ("system-path", self.system_path()),
            ("modules", self.modules()),
            ("firmware", self.firmware()),
        ] {
            if !p.exists() {
                return Err(io::Error::new(
                    io::ErrorKind::NotFound,
                    format!("core link '{name}' not found at: {}", p.display()),
                ));
            }
        }
        Ok(())
    }
}

/// 稼働中の世代 (/run/current-system) と、ブート時の世代 (/run/booted-system)
pub fn current() -> io::Result<Core> {
    Core::load(Path::new("/run/current-system"))
}

pub fn booted() -> io::Result<Core> {
    Core::load(Path::new("/run/booted-system"))
}
