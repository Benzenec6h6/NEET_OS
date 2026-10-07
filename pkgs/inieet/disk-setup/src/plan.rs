//! disk-plan.json の型定義とバリデーション

use crate::layout::{parse_size, SizeSpec};
use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::Path;

#[derive(Debug, Deserialize, Clone)]
pub struct Plan {
    pub version: u32,
    pub disks: Vec<Disk>,
}

#[derive(Debug, Deserialize, Clone)]
pub struct Disk {
    pub name: String,
    /// 実機のデバイス。イメージ生成では使わない。`--device` で上書き可能
    #[serde(default)]
    pub device: Option<String>,
    /// GPT 上の順序そのまま（番号は 1 始まりで位置から決まる）
    pub partitions: Vec<Partition>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Partition {
    pub name: String,
    /// "512M" / "4G" / "100%"（残り全部。最後のパーティションのみ）
    pub size: String,
    /// sgdisk の typecode（例: ef00, 8300, 8200）
    pub type_code: String,
    pub guid: String,
    #[serde(default)]
    pub content: Option<Content>,
}

#[derive(Debug, Deserialize, Clone, Copy, PartialEq, Eq)]
#[serde(rename_all = "lowercase")]
pub enum FsKind {
    Vfat,
    Ext4,
    Btrfs,
    Swap,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Content {
    #[serde(rename = "type")]
    pub kind: FsKind,
    pub label: String,
    /// vfat は "ABCD-1234"（ボリュームID）、それ以外は UUID
    pub uuid: String,
    #[serde(default)]
    pub mount_point: Option<String>,
    #[serde(default)]
    pub mount_options: Vec<String>,
    #[serde(default)]
    pub mkfs_args: Vec<String>,
    #[serde(default)]
    pub subvolumes: Vec<Subvolume>,
}

#[derive(Debug, Deserialize, Clone)]
#[serde(rename_all = "camelCase")]
pub struct Subvolume {
    pub name: String,
    #[serde(default)]
    pub mount_point: Option<String>,
    #[serde(default)]
    pub options: Vec<String>,
}

/// 1 回の mount に相当する単位（btrfs は subvolume ごとに 1 つ）
#[derive(Debug, Clone, PartialEq, Eq)]
pub struct MountSpec {
    pub mount_point: String,
    pub options: Vec<String>,
    pub subvol: Option<String>,
}

impl Content {
    pub fn fs_type(&self) -> &'static str {
        match self.kind {
            FsKind::Vfat => "vfat",
            FsKind::Ext4 => "ext4",
            FsKind::Btrfs => "btrfs",
            FsKind::Swap => "swap",
        }
    }

    pub fn mounts(&self) -> Vec<MountSpec> {
        match self.kind {
            FsKind::Swap => vec![],
            FsKind::Btrfs if !self.subvolumes.is_empty() => self
                .subvolumes
                .iter()
                .filter_map(|sv| {
                    let mount_point = sv.mount_point.clone()?;
                    let mut options = vec![format!("subvol={}", sv.name)];
                    options.extend(sv.options.iter().cloned());
                    Some(MountSpec {
                        mount_point,
                        options,
                        subvol: Some(sv.name.clone()),
                    })
                })
                .collect(),
            _ => self
                .mount_point
                .iter()
                .map(|mp| MountSpec {
                    mount_point: mp.clone(),
                    options: self.mount_options.clone(),
                    subvol: None,
                })
                .collect(),
        }
    }
}

impl Plan {
    pub fn load(path: &Path) -> io::Result<Plan> {
        let data = fs::read_to_string(path)?;
        let plan: Plan = serde_json::from_str(&data)
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        plan.validate()
            .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
        Ok(plan)
    }

    /// Nix 側の assertions の最終防衛線（手書き JSON でも壊れないように）
    pub fn validate(&self) -> Result<(), String> {
        if self.version != 1 {
            return Err(format!("unsupported plan version {}", self.version));
        }
        let mut seen = HashSet::new();
        for d in &self.disks {
            let n = d.partitions.len();
            for (i, p) in d.partitions.iter().enumerate() {
                if parse_size(&p.size)? == SizeSpec::Rest && i + 1 != n {
                    return Err(format!(
                        "{}/{}: '100%' is only allowed on the last partition",
                        d.name, p.name
                    ));
                }
                let Some(c) = &p.content else { continue };
                for m in c.mounts() {
                    if !m.mount_point.starts_with('/') {
                        return Err(format!("mount point must be absolute: {}", m.mount_point));
                    }
                    if !seen.insert(m.mount_point.clone()) {
                        return Err(format!("duplicate mount point: {}", m.mount_point));
                    }
                }
            }
        }
        Ok(())
    }

    /// 全ディスクのマウントポイント（イメージ生成時の「入れ子の除外」に使う）
    pub fn all_mount_points(&self) -> Vec<String> {
        self.disks
            .iter()
            .flat_map(|d| d.partitions.iter())
            .filter_map(|p| p.content.as_ref())
            .flat_map(|c| c.mounts())
            .map(|m| m.mount_point)
            .collect()
    }

    pub fn select_disk(&self, name: Option<&str>) -> Result<&Disk, String> {
        match (name, self.disks.as_slice()) {
            (Some(n), disks) => disks
                .iter()
                .find(|d| d.name == n)
                .ok_or_else(|| format!("disk '{n}' not found in plan")),
            (None, [only]) => Ok(only),
            (None, []) => Err("plan has no disks".into()),
            (None, _) => Err("plan has multiple disks; specify --disk NAME".into()),
        }
    }
}

#[cfg(test)]
pub(crate) mod tests {
    use super::*;

    pub const SAMPLE: &str = r#"{
      "version": 1,
      "disks": [{
        "name": "main",
        "device": null,
        "partitions": [
          {"name":"esp","size":"512M","typeCode":"ef00","guid":"11111111-1111-4111-8111-111111111111",
           "content":{"type":"vfat","label":"ESP","uuid":"ABCD-1234","mountPoint":"/boot","mountOptions":["defaults"]}},
          {"name":"root","size":"100%","typeCode":"8300","guid":"22222222-2222-4222-8222-222222222222",
           "content":{"type":"btrfs","label":"root","uuid":"33333333-3333-4333-8333-333333333333",
             "mountPoint":null,"mountOptions":[],
             "subvolumes":[
               {"name":"@root","mountPoint":"/","options":[]},
               {"name":"@nix","mountPoint":"/nix","options":["noatime"]},
               {"name":"@scratch","mountPoint":null,"options":[]}]}}
        ]}]}"#;

    pub fn sample() -> Plan {
        let p: Plan = serde_json::from_str(SAMPLE).unwrap();
        p.validate().unwrap();
        p
    }

    #[test]
    fn mounts_expand_subvolumes() {
        let p = sample();
        let c = p.disks[0].partitions[1].content.as_ref().unwrap();
        let m = c.mounts();
        assert_eq!(m.len(), 2); // mountPoint 無しの @scratch は mount されない
        assert_eq!(m[1].mount_point, "/nix");
        assert_eq!(m[1].options, ["subvol=@nix", "noatime"]);
        assert_eq!(p.all_mount_points(), ["/boot", "/", "/nix"]);
    }

    #[test]
    fn rest_must_be_last_and_mounts_unique() {
        let mut p = sample();
        p.disks[0].partitions[0].size = "100%".into();
        assert!(p.validate().is_err());

        let mut p = sample();
        p.disks[0].partitions[0].content.as_mut().unwrap().mount_point = Some("/nix".into());
        assert!(p.validate().unwrap_err().contains("duplicate"));
    }

    #[test]
    fn select_disk_rules() {
        let p = sample();
        assert_eq!(p.select_disk(None).unwrap().name, "main");
        assert!(p.select_disk(Some("x")).is_err());
    }
}
