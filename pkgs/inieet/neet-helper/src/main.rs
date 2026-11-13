mod builder;
mod diff;
mod privileged;

use clap::{Parser, Subcommand};
use colored::*;
use neet_core::manifest::{self};
use privileged::PrivOp;
use std::io::{self, Write};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "neet", about = "NEET OS System Helper CLI")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// OS のビルド、切り替え、世代管理
    Os {
        #[command(subcommand)]
        action: OsAction,
    },
    /// 特権側ヘルパー (neet-admin-server から呼ばれる。直接は使わない)
    #[command(hide = true)]
    Priv {
        #[command(subcommand)]
        op: PrivOp,
    },
}

fn default_flake_path() -> PathBuf {
    std::env::var("NEET_FLAKE")
        .map(PathBuf::from)
        .unwrap_or_else(|_| PathBuf::from("/etc/neet-os"))
}

#[derive(Subcommand)]
enum OsAction {
    Switch {
        #[arg(default_value_os_t = default_flake_path())]
        flake_path: PathBuf,

        #[arg(short, long)]
        yes: bool,

        #[arg(short, long)]
        force: bool,

        #[arg(short, long)]
        attr: Option<String>,
    },
    Diff {
        #[arg(default_value_os_t = default_flake_path())]
        flake_path: PathBuf,

        #[arg(short, long)]
        attr: Option<String>,
    },
    Boot {
        #[arg(default_value_os_t = default_flake_path())]
        flake_path: PathBuf,

        #[arg(short, long)]
        attr: Option<String>,
    },
    List,
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Priv { op } => privileged::serve(op)?,
        Commands::Os { action } => match action {
            OsAction::Switch {
                flake_path,
                yes,
                force,
                attr,
            } => {
                let build = builder::build_system(&flake_path, attr.as_deref())?;
                let current_core = manifest::current().ok();
                diff::print_full_diff(current_core.as_ref(), &build.core)?;

                if !yes {
                    print!("Proceed to switch configuration? [Y/n]: ");
                    io::stdout().flush()?;
                    let mut input = String::new();
                    io::stdin().read_line(&mut input)?;
                    let input = input.trim();
                    if !input.is_empty() && !input.eq_ignore_ascii_case("y") {
                        println!("Aborted.");
                        return Ok(());
                    }
                }
                privileged::invoke(&PrivOp::Switch {
                    toplevel: build.toplevel.clone(),
                    force,
                })?;
            }

            OsAction::Diff { flake_path, attr } => {
                let build = builder::build_system(&flake_path, attr.as_deref())?;
                let current_core = manifest::current().ok();
                diff::print_full_diff(current_core.as_ref(), &build.core)?;
            }

            OsAction::Boot { flake_path, attr } => {
                let build = builder::build_system(&flake_path, attr.as_deref())?;
                privileged::invoke(&PrivOp::Boot {
                    toplevel: build.toplevel.clone(),
                })?;
            }

            OsAction::List => {
                let (gens, skipped) = neet_core::generation::list(std::path::Path::new(
                    neet_core::generation::PROFILES,
                ))?;
                println!("{}", "=== System Generations ===".bold());
                for gen in gens {
                    println!("  Generation {:>3}: {}", gen.number, gen.toplevel.display());
                }
                for (num, err) in skipped {
                    eprintln!("  Generation {:>3}: (error: {})", num, err);
                }
            }
        },
    }

    Ok(())
}
