use anyhow::{Context, Result};
use neet_core::manifest::Core;
use std::path::Path;
use std::process::Command;

/// root でなければ s6-sudo を使って管理者ソケット経由で実行する
fn run_privileged(program: &str, args: &[&str]) -> Result<()> {
    let is_root = nix::unistd::Uid::current().is_root();

    let mut cmd = if is_root {
        Command::new(program)
    } else {
        let sock =
            std::env::var("NEET_ADMIN_SOCK").unwrap_or_else(|_| "/run/neet-admin.sock".to_string());

        let mut c = Command::new("s6-sudo");
        c.arg(sock);
        c.arg(program);
        c
    };

    cmd.args(args);

    let status = cmd
        .status()
        .with_context(|| format!("Failed to execute {}", program))?;
    if !status.success() {
        anyhow::bail!("Command '{}' failed with exit status: {}", program, status);
    }
    Ok(())
}

pub fn switch(toplevel: &Path, core: &Core, force: bool) -> Result<()> {
    // 1. プロファイル更新 (s6-sudo 経由で root 実行)
    println!("==> [neet] Updating system profile...");
    run_privileged(
        "nix-env",
        &[
            "-p",
            "/nix/var/nix/profiles/system",
            "--set",
            toplevel.to_str().unwrap(),
        ],
    )?;

    // 2. ブートローダ同期
    let bootloader = toplevel.join("bin/install-bootloader");
    if bootloader.exists() {
        println!("==> [neet] Updating bootloader...");
        let _ = run_privileged(bootloader.to_str().unwrap(), &[]);
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

    // 4. neet-activate switch の実行
    println!("==> [neet] Activating live configuration...");
    run_privileged("neet-activate", &["switch", core.path.to_str().unwrap()])?;

    // 5. システム s6-rc-update
    let live_s6 = Path::new("/run/s6-rc");
    if let Some(s6_db) = core.s6_rc() {
        if live_s6.exists() {
            println!("==> [neet] Updating system s6-rc service database...");
            let _ = run_privileged(
                "s6-rc-update",
                &["-l", "/run/s6-rc", s6_db.to_str().unwrap()],
            );
        }
    }

    println!("==> [neet] Successfully switched to new configuration!");
    Ok(())
}

pub fn boot(toplevel: &Path) -> Result<()> {
    println!("==> [neet] Updating system profile...");
    run_privileged(
        "nix-env",
        &[
            "-p",
            "/nix/var/nix/profiles/system",
            "--set",
            toplevel.to_str().unwrap(),
        ],
    )?;

    let bootloader = toplevel.join("bin/install-bootloader");
    if bootloader.exists() {
        println!("==> [neet] Updating bootloader...");
        let _ = run_privileged(bootloader.to_str().unwrap(), &[]);
    }
    println!("==> [neet] Boot configuration updated. Will take effect on next reboot.");
    Ok(())
}
