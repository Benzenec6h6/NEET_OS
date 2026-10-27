use serde::Deserialize;
use std::path::PathBuf;

#[derive(Debug, Deserialize)]
pub struct SecretsManifest {
    pub secrets: Vec<SecretEntry>,
}

#[derive(Debug, Deserialize)]
pub struct SecretEntry {
    /// 識別名（例: "db-password", "wg-private-key"）
    pub name: String,

    /// 暗号化された .age ファイルへのパス (Nix Store 内のパスなど)
    pub encrypted_file: PathBuf,

    /// 所有ユーザー名 (例: "root", "sshd")
    pub owner: String,

    /// 所有グループ名 (例: "root", "sshd")
    pub group: String,

    /// パーミッション（8進数表記、例: 0o400）
    pub mode: u32,

    /// ファイルとして直接特定のパスへ配置したい場合のパス (オプション)
    /// 未指定の場合は /run/secrets/by-name/<name> に配置
    pub path: Option<PathBuf>,

    /// s6-envdir 向けに配置する場合の設定 (オプション)
    pub env: Option<EnvConfig>,
}

#[derive(Debug, Deserialize)]
pub struct EnvConfig {
    /// 対象の s6 サービス名（例: "my-service"）
    /// 配置先: /run/secrets/env/<service>/<var>
    pub service: String,

    /// 環境変数名（例: "DATABASE_PASSWORD"）
    pub var: String,
}
