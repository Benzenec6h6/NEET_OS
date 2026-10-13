use serde::Deserialize;
use std::collections::HashSet;
use std::fs;
use std::io;
use std::path::Path;
use std::process::Command;

const MANIFEST_PATH: &str = "/etc/nftables/manifest.json";

#[derive(Debug, Deserialize)]
struct FirewallManifest {
    tables: Vec<ManagedTable>,
}

#[derive(Debug, Deserialize, PartialEq, Eq, Hash, Clone)]
struct ManagedTable {
    name: String,
    family: String,
    path: String,
}

// nft -j list tables のパース用構造体
#[derive(Debug, Deserialize)]
struct NftOutput {
    nftables: Vec<NftItem>,
}

#[derive(Debug, Deserialize)]
#[serde(rename_all = "lowercase")]
enum NftItem {
    Table {
        family: String,
        name: String,
    },
    #[serde(other)]
    Other,
}

pub fn sync_firewall() -> io::Result<()> {
    let manifest_file = Path::new(MANIFEST_PATH);
    if !manifest_file.exists() {
        println!("system-init: [firewall] no manifest found, skipping.");
        return Ok(());
    }

    // 1. 今回の世代のマニフェストを読み込む
    let manifest_raw = fs::read_to_string(manifest_file)?;
    let manifest: FirewallManifest = serde_json::from_str(&manifest_raw)
        .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;

    // 2. 現在カーネルに存在するテーブルを取得 (`nft -j list tables`)
    let output = Command::new("nft")
        .args(["-j", "list", "tables"])
        .output()
        .map_err(|e| io::Error::new(e.kind(), format!("failed to execute nft: {e}")))?;

    let mut current_kernel_tables: HashSet<(String, String)> = HashSet::new();
    if output.status.success() {
        if let Ok(parsed) = serde_json::from_slice::<NftOutput>(&output.stdout) {
            for item in parsed.nftables {
                if let NftItem::Table { family, name } = item {
                    current_kernel_tables.insert((family, name));
                }
            }
        }
    }

    // 今回適用したいテーブルの (family, name) セット
    let desired_tables: HashSet<(String, String)> = manifest
        .tables
        .iter()
        .map(|t| (t.family.clone(), t.name.clone()))
        .collect();

    // 3. 【Diffの削除】
    // 過去に NEET_OS が作った記録など、または特定プレフィックスの消去
    // （※シンプルにするなら、前回のマニフェストキャッシュ /var/lib/nftables/prev.json と比較）
    let state_cache = Path::new("/var/lib/nftables/previous_manifest.json");
    if state_cache.exists() {
        if let Ok(prev_raw) = fs::read_to_string(state_cache) {
            if let Ok(prev_manifest) = serde_json::from_str::<FirewallManifest>(&prev_raw) {
                for prev in prev_manifest.tables {
                    let key = (prev.family.clone(), prev.name.clone());
                    // 「前世代にあったが、新世代にはなく、現在カーネルに残っている」テーブルを削除
                    if !desired_tables.contains(&key) && current_kernel_tables.contains(&key) {
                        println!(
                            "system-init: [firewall] deleting obsolete table: {} {}",
                            prev.family, prev.name
                        );
                        let _ = Command::new("nft")
                            .args(["delete", "table", &prev.family, &prev.name])
                            .status();
                    }
                }
            }
        }
    }

    // 4. 【テーブルの適用】
    // アトミックに各ルールファイルを適用 (`nft -f <path>`)
    for table in &manifest.tables {
        println!(
            "system-init: [firewall] applying table: {} {}",
            table.family, table.name
        );

        // 構文チェック
        let check = Command::new("nft")
            .args(["-c", "-f", &table.path])
            .status()?;
        if !check.success() {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("syntax error in {}", table.path),
            ));
        }

        // 適用
        let status = Command::new("nft").args(["-f", &table.path]).status()?;
        if !status.success() {
            return Err(io::Error::new(
                io::ErrorKind::Other,
                format!("failed to load {}", table.path),
            ));
        }
    }

    // 5. 次回比較のために今回のマニフェストをキャッシュ
    let _ = fs::create_dir_all("/var/lib/nftables");
    let _ = fs::write(state_cache, manifest_raw);

    println!("system-init: [firewall] firewall synchronized successfully.");
    Ok(())
}
