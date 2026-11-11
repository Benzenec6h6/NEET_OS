pub mod packages;
pub mod reboot;
pub mod s6;
pub mod state;

use anyhow::Result;
use colored::*;
use neet_core::manifest::Core;

pub fn print_full_diff(old_core: Option<&Core>, new_core: &Core) -> Result<()> {
    println!("\n{}", "=== NEET OS Configuration Diff ===".bold().cyan());

    if let Some(old) = old_core {
        packages::diff_packages(&old.system_path(), &new_core.system_path())?;
        println!();
        s6::diff_system_s6(&old.etc(), &new_core.etc())?;
        println!();
        s6::diff_user_s6(&old.etc(), &new_core.etc())?;
        println!();
        state::diff_state_directories(&old.etc(), &new_core.etc())?;
        println!();
    } else {
        println!("(No current-system found. Initial deployment)");
    }

    if let Some(reboot_msg) = reboot::check_reboot_required(new_core)? {
        println!("{}", format!("⚠️  NOTICE: {}", reboot_msg).bold().yellow());
        println!(
            "{}",
            "   A reboot is required for these changes to fully take effect.\n".yellow()
        );
    }

    Ok(())
}
