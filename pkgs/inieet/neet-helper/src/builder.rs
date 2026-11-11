use anyhow::{Context, Result};
use neet_core::manifest::Core;
use std::path::{Path, PathBuf};
use std::process::Command;

pub struct BuildResult {
    pub toplevel: PathBuf,
    pub core: Core,
}

pub fn build_system(flake_path: &Path, package_attr: Option<&str>) -> Result<BuildResult> {
    let attr = package_attr.unwrap_or("packages.x86_64-linux.default");
    let installable = format!("{}#{}", flake_path.display(), attr);

    println!("==> [neet] Building system from {}...", installable);

    let output = Command::new("nix")
        .args(["build", &installable, "--no-link", "--print-out-paths"])
        .output()
        .context("Failed to run 'nix build'")?;

    if !output.status.success() {
        let err = String::from_utf8_lossy(&output.stderr);
        anyhow::bail!("nix build failed:\n{}", err);
    }

    let toplevel_str = String::from_utf8_lossy(&output.stdout).trim().to_string();
    let toplevel = PathBuf::from(toplevel_str);

    println!("==> [neet] Built toplevel: {}", toplevel.display());

    let core = Core::load(&toplevel).context("Failed to load core manifest from toplevel")?;

    Ok(BuildResult { toplevel, core })
}
