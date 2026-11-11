use anyhow::{Context, Result};
use neet_core::manifest::Core;
use std::path::Path;
use std::process::Command;

pub fn switch(toplevel: &Path, core: &Core, force: bool) -> Result<()> {
    // 1. プロファイル更新
    println!("==> [neet] Updating system profile...");
    let status = Command::new("nix-env")
        .args([
            "-p",
            "/nix/var/nix/profiles/system",
            "--set",
            toplevel.to_str().unwrap(),
        ])
        .status()?;
    if !status.success() {
        anyhow::bail!("Failed to update /nix/var/nix/profiles/system");
    }

    // 2. ブートローダ同期
    let bootloader = toplevel.join("bin/install-bootloader");
    if bootloader.exists() {
        println!("==> [neet] Updating bootloader...");
        let status = Command::new(&bootloader).status()?;
        if !status.success() {
            eprintln!("==> [neet] warning: install-bootloader exited with non-zero status");
        }
    }

    // 3. 再起動要否の検査
    if let Some(reason) = crate::diff::reboot::check_reboot_required(core)? {
        if !force {
            println!("--------------------------------------------------");
            println!(" [NOTICE] Live switch skipped: {}", reason);
            println!(" Bootloader is updated. Please reboot your system!");
            println!(" (To force live switch anyway, use --force)");
            println!("--------------------------------------------------");
            return Ok(());
        }
        println!("==> [neet] Forcing live switch despite reboot notice...");
    }

    // 4. neet-activate switch の実行 (/etc, ラッパー, /bin の切り替え)
    println!("==> [neet] Activating live configuration...");
    let status = Command::new("neet-activate")
        .args(["switch", core.path.to_str().unwrap()])
        .status()
        .context("Failed to execute neet-activate")?;
    if !status.success() {
        anyhow::bail!("neet-activate failed");
    }

    // 5. システム s6-rc-update
    let live_s6 = Path::new("/run/s6-rc");
    if let Some(s6_db) = core.s6_rc() {
        if live_s6.exists() {
            println!("==> [neet] Updating system s6-rc service database...");
            let _ = Command::new("s6-rc-update")
                .args(["-l", "/run/s6-rc", s6_db.to_str().unwrap()])
                .status();
        }
    }

    println!("==> [neet] Successfully switched to new configuration!");
    Ok(())
}

pub fn boot(toplevel: &Path) -> Result<()> {
    println!("==> [neet] Updating system profile...");
    Command::new("nix-env")
        .args([
            "-p",
            "/nix/var/nix/profiles/system",
            "--set",
            toplevel.to_str().unwrap(),
        ])
        .status()?;

    let bootloader = toplevel.join("bin/install-bootloader");
    if bootloader.exists() {
        println!("==> [neet] Updating bootloader...");
        Command::new(bootloader).status()?;
    }
    println!("==> [neet] Boot configuration updated. Will take effect on next reboot.");
    Ok(())
}
