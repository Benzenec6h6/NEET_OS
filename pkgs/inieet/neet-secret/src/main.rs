mod decrypt;
mod manifest;
mod tpm;

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
    /// マニフェストに従ってシークレットを一括復号し、ディレクトリに展開する (Stage 2)
    Decrypt {
        #[arg(short, long, default_value = "/etc/secrets-manifest.json")]
        manifest: PathBuf,

        /// SSH 秘密鍵のパス
        #[arg(short, long, default_value = "/var/lib/sshd/ssh_host_ed25519_key")]
        key: PathBuf,

        /// TPM 2.0 (NVRAM) から復号鍵を取得する
        #[arg(long)]
        tpm: bool,

        /// TPM NVRAM のインデックス (デフォルト: 0x01500000)
        #[arg(
            long,
            default_value_t = tpm::DEFAULT_AGE_NV_INDEX,
            value_parser = parse_hex_or_dec
        )]
        tpm_nv_index: u32,

        #[arg(short, long, default_value = "/run/secrets")]
        out_dir: PathBuf,
    },

    /// 単一の .age ファイルを復号して標準出力 (stdout) に出力する (Stage 1 / LUKS 解錠パイプ用)
    Print {
        /// 暗号化された .age ファイル
        file: PathBuf,

        /// SSH 秘密鍵のパス
        #[arg(short, long)]
        key: Option<PathBuf>,

        /// TPM 2.0 (NVRAM) から復号鍵を取得する
        #[arg(long)]
        tpm: bool,

        /// TPM NVRAM のインデックス (デフォルト: 0x01500000)
        #[arg(
            long,
            default_value_t = tpm::DEFAULT_AGE_NV_INDEX,
            value_parser = parse_hex_or_dec
        )]
        tpm_nv_index: u32,
    },
}

/// 16進数 ("0x...") または 10進数の文字列を u32 にパースする
fn parse_hex_or_dec(s: &str) -> Result<u32, String> {
    if let Some(stripped) = s.strip_prefix("0x") {
        u32::from_str_radix(stripped, 16).map_err(|e| format!("Invalid hex index: {}", e))
    } else {
        s.parse::<u32>()
            .map_err(|e| format!("Invalid index: {}", e))
    }
}

fn main() -> anyhow::Result<()> {
    let cli = Cli::parse();

    match cli.command {
        Commands::Decrypt {
            manifest,
            key,
            tpm,
            tpm_nv_index,
            out_dir,
        } => {
            if !manifest.exists() {
                println!("neet-secret: no secrets manifest found. Skipping.");
                return Ok(());
            }

            let identity = if tpm {
                // すでに u32 にパース済みなのでそのまま渡せる
                tpm::load_tpm_identity(tpm_nv_index)?
            } else {
                decrypt::load_ssh_identity(&key)?
            };

            decrypt::run_decrypt(&manifest, identity.as_ref(), &out_dir)?;
        }

        Commands::Print {
            file,
            key,
            tpm,
            tpm_nv_index,
        } => {
            let identity = if tpm {
                // すでに u32 にパース済みなのでそのまま渡せる
                tpm::load_tpm_identity(tpm_nv_index)?
            } else if let Some(key_path) = key {
                decrypt::load_ssh_identity(&key_path)?
            } else {
                anyhow::bail!("Either --tpm or --key must be specified for print");
            };

            decrypt::print_secret(&file, identity.as_ref())?;
        }
    }

    Ok(())
}
