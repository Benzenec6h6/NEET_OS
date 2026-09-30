use serde::{Deserialize, Serialize};
use std::collections::BTreeMap;

#[derive(Debug, Serialize, Deserialize)]
#[serde(deny_unknown_fields)] // ← ここがCUEのスキーマ検証に相当する
pub struct BootspecV1 {
    pub system: String,
    pub init: String,
    #[serde(skip_serializing_if = "Option::is_none")]
    pub initrd: Option<String>,
    pub kernel: String,
    #[serde(rename = "kernelParams")]
    pub kernel_params: Vec<String>,
    pub label: String,
    pub toplevel: String,
    #[serde(skip_serializing_if = "Option::is_none", default)]
    pub uki: Option<String>,
}

#[derive(Debug, Serialize, Deserialize)]
pub struct Document {
    #[serde(rename = "org.nixos.bootspec.v1")]
    pub bootspec: BootspecV1,
    #[serde(
        rename = "org.nixos.specialisation.v1",
        skip_serializing_if = "Option::is_none",
        default
    )]
    pub specialisations: Option<BTreeMap<String, Document>>,
}

impl BootspecV1 {
    /// パスが実際にNix storeなどに存在するかまで検証したい場合はここに追加
    pub fn validate_paths_exist(&self) -> Result<(), String> {
        for p in [&self.init, &self.kernel] {
            if !std::path::Path::new(p).exists() {
                return Err(format!("path does not exist: {p}"));
            }
        }
        Ok(())
    }
}
