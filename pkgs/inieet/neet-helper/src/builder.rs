use anyhow::{Context, Result};
use neet_core::manifest::Core;
use std::io::Read;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};

pub struct BuildResult {
    pub toplevel: PathBuf,
    pub core: Core,
}

pub fn build_system(flake_path: &Path, package_attr: Option<&str>) -> Result<BuildResult> {
    let attr = package_attr.unwrap_or("packages.x86_64-linux.default");
    let installable = format!("{}#{}", flake_path.display(), attr);

    println!("==> [neet] Building system from {}...", installable);

    let rom_bin = std::env::var("NEET_ROM")
        .ok()
        .or_else(|| option_env!("ROM_PATH").map(String::from))
        .unwrap_or_else(|| "rom".into());

    let mut nix_child = Command::new("nix")
        .args([
            "build",
            &installable,
            "--no-link",
            "--print-out-paths",
            "--log-format",
            "internal-json",
        ])
        .stdout(Stdio::piped())
        .stderr(Stdio::piped())
        .spawn()
        .context("Failed to run 'nix build'")?;

    let mut nix_stdout = nix_child
        .stdout
        .take()
        .context("Failed to capture nix stdout")?;
    let nix_stderr = nix_child
        .stderr
        .take()
        .context("Failed to capture nix stderr")?;

    // nix の stderr (@nix ログ) を rom の stdin に直結してターミナルへ描画させる
    let mut rom_child = Command::new(&rom_bin)
        .stdin(Stdio::from(nix_stderr))
        .stdout(Stdio::inherit())
        .stderr(Stdio::inherit())
        .spawn()
        .with_context(|| format!("Failed to spawn '{}'", rom_bin))?;

    // stdout (--print-out-paths の結果) を読み取る
    let mut toplevel_raw = String::new();
    nix_stdout.read_to_string(&mut toplevel_raw)?;

    let nix_status = nix_child.wait()?;
    let _ = rom_child.wait();

    if !nix_status.success() {
        anyhow::bail!("nix build failed with status: {}", nix_status);
    }

    let toplevel = PathBuf::from(toplevel_raw.trim());
    println!("==> [neet] Built toplevel: {}", toplevel.display());

    let core = Core::load(&toplevel).context("Failed to load core manifest from toplevel")?;

    Ok(BuildResult { toplevel, core })
}
