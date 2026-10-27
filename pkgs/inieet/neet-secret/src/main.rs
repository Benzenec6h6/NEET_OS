mod decrypt;
mod manifest;

use clap::{Parser, Subcommand};
use std::path::PathBuf;

#[derive(Parser)]
#[command(name = "neet-secret")]
#[command(about = "Secret management tool for NEET_OS")]
struct Cli {
    #[command(subcommand)]
    command: Commands,
}

#[derive(Subcommand)]
enum Commands {
    /// システム起動時・更新時にシークレットを復号して展開する
    Decrypt {
        /// マニフェストJSONのパス
        #[arg(short, long, default_value = "/etc/secrets-manifest.json")]
        manifest: PathBuf,

        /// 復号に使用するSSH秘密鍵のパス
        #[arg(short, long, default_value = "/var/lib/sshd/ssh_host_ed25519_key")]
        key: PathBuf,

        /// シークレットの展開先ベースディレクトリ
        #[arg(short, long, default_value = "/run/secrets")]
        out_dir: PathBuf,
    },
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Decrypt {
            manifest,
            key,
            out_dir,
        } => {
            if !manifest.exists() {
                // マニフェストが無い（シークレットが1つも定義されていない）場合は何もしない
                println!("neet-secret: no secrets manifest found. Skipping.");
                return Ok(());
            }
            decrypt::run_decrypt(&manifest, &key, &out_dir)?;
        }
    }

    Ok(())
}
