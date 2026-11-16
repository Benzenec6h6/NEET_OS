use anyhow::{Context, Result};
use colored::*;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet, HashMap, VecDeque};
use std::fs;
use std::path::Path;

#[derive(Debug, Clone, Deserialize, PartialEq, Eq)]
#[serde(rename_all = "camelCase")]
pub struct S6ServiceMeta {
    pub r#type: String,
    #[serde(default)]
    pub dependencies: Vec<String>,
    pub auto_start: bool,
    #[serde(default)]
    pub part_of: Vec<String>,
    #[serde(default)]
    pub load_secrets: bool,
    #[serde(default)]
    pub envdirs: Vec<String>,
    #[serde(default)]
    pub format: Option<String>,
    #[serde(default)]
    pub notification_fd: Option<i64>,
    pub script_hash: Option<String>,
    #[serde(default)]
    pub logger_hash: Option<String>,
}

#[derive(Debug, Deserialize)]
pub struct UserMeta {
    pub uid: Option<u32>,
    pub gid: Option<u32>,
    pub services: HashMap<String, S6ServiceMeta>,
}

pub fn diff_system_s6(old_etc: &Path, new_etc: &Path) -> Result<bool> {
    println!("{}", "[s6-rc System Services]".bold());
    let old_map: HashMap<String, S6ServiceMeta> =
        read_json_or_empty(&old_etc.join("s6-rc/services.json"))?;
    let new_map: HashMap<String, S6ServiceMeta> =
        read_json_or_empty(&new_etc.join("s6-rc/services.json"))?;
    diff_service_flat(&old_map, &new_map, "  ")
}

pub fn diff_user_s6(old_etc: &Path, new_etc: &Path) -> Result<bool> {
    let old_users: HashMap<String, UserMeta> =
        read_json_or_empty(&old_etc.join("s6-rc/users-services.json"))?;
    let new_users: HashMap<String, UserMeta> =
        read_json_or_empty(&new_etc.join("s6-rc/users-services.json"))?;

    let all_users: BTreeSet<_> = old_users.keys().chain(new_users.keys()).collect();
    let empty_services: HashMap<String, S6ServiceMeta> = HashMap::new();
    let mut changed = false;

    for user in all_users {
        let user_meta = new_users.get(user).or_else(|| old_users.get(user));
        let id_str = match (user_meta.and_then(|u| u.uid), user_meta.and_then(|u| u.gid)) {
            (Some(uid), Some(gid)) => format!(" ({}:{})", uid, gid),
            (Some(uid), None) => format!(" (UID: {})", uid),
            _ => String::new(),
        };

        println!(
            "{}",
            format!("[s6-rc User Services: {}{}]", user, id_str).bold()
        );

        let old_svcs = old_users
            .get(user)
            .map(|u| &u.services)
            .unwrap_or(&empty_services);
        let new_svcs = new_users
            .get(user)
            .map(|u| &u.services)
            .unwrap_or(&empty_services);

        if diff_service_flat(old_svcs, new_svcs, "  ")? {
            changed = true;
        }
    }
    Ok(changed)
}

fn diff_service_flat(
    old_map: &HashMap<String, S6ServiceMeta>,
    new_map: &HashMap<String, S6ServiceMeta>,
    indent: &str,
) -> Result<bool> {
    let mut added = BTreeSet::new();
    let mut removed = BTreeSet::new();
    let mut directly_changed = BTreeSet::new();

    // 1. 追加・削除・直接変更の検出 (仮想グループの bundle はプロセスを持たないため除外)
    for (name, new_meta) in new_map {
        if new_meta.r#type == "bundle" {
            continue;
        }
        match old_map.get(name) {
            None => {
                added.insert(name.clone());
            }
            Some(old_meta) => {
                if is_directly_changed(old_meta, new_meta) {
                    directly_changed.insert(name.clone());
                }
            }
        }
    }

    for (name, old_meta) in old_map {
        if old_meta.r#type == "bundle" {
            continue;
        }
        if !new_map.contains_key(name) {
            removed.insert(name.clone());
        }
    }

    // 2. 逆依存マップの構築 (dep -> このサービスに依存しているサービスのリスト)
    let mut dependents: HashMap<String, Vec<String>> = HashMap::new();
    for (name, meta) in new_map {
        for dep in &meta.dependencies {
            dependents
                .entry(dep.clone())
                .or_default()
                .push(name.clone());
        }
    }

    // 3. BFS で波及した再起動サービスとその原因 (via) を特定
    // service -> Option<cause> (None = 直接変更, Some(cause) = 波及元)
    let mut restarted: BTreeMap<String, Option<String>> = BTreeMap::new();
    let mut queue = VecDeque::new();

    for direct in &directly_changed {
        restarted.insert(direct.clone(), None);
        queue.push_back((direct.clone(), direct.clone()));
    }

    while let Some((curr, root_cause)) = queue.pop_front() {
        if let Some(children) = dependents.get(&curr) {
            for child in children {
                // bundle は除外
                if let Some(child_meta) = new_map.get(child) {
                    if child_meta.r#type == "bundle" {
                        continue;
                    }
                }

                // まだ未登録なら、原因 (root_cause) を付けて追加
                if !restarted.contains_key(child) {
                    restarted.insert(child.clone(), Some(root_cause.clone()));
                    queue.push_back((child.clone(), root_cause.clone()));
                }
            }
        }
    }

    // 4. 差分が一切なければ (no changes)
    if added.is_empty() && removed.is_empty() && restarted.is_empty() {
        println!("{}(no changes)", indent);
        return Ok(false);
    }

    // 5. フラットな集合として出力
    if !restarted.is_empty() {
        let items: Vec<String> = restarted
            .into_iter()
            .map(|(svc, via)| match via {
                Some(cause) => format!("{} {}", svc, format!("(via {})", cause).dimmed()),
                None => svc.bold().to_string(),
            })
            .collect();
        println!(
            "{}{}: {}",
            indent,
            format!("Restarted ({})", items.len()).yellow().bold(),
            items.join(", ")
        );
    }

    if !added.is_empty() {
        let items: Vec<String> = added.into_iter().map(|s| s.green().to_string()).collect();
        println!(
            "{}{}: {}",
            indent,
            format!("Added ({})", items.len()).green().bold(),
            items.join(", ")
        );
    }

    if !removed.is_empty() {
        let items: Vec<String> = removed.into_iter().map(|s| s.red().to_string()).collect();
        println!(
            "{}{}: {}",
            indent,
            format!("Removed ({})", items.len()).red().bold(),
            items.join(", ")
        );
    }

    Ok(true)
}

/// サービス定義が直接書き換えられたかどうかの判定
fn is_directly_changed(old: &S6ServiceMeta, new: &S6ServiceMeta) -> bool {
    old.r#type != new.r#type
        || old.script_hash != new.script_hash
        || old.logger_hash != new.logger_hash
        || old.envdirs != new.envdirs
        || old.dependencies != new.dependencies
        || old.notification_fd != new.notification_fd
        || old.format != new.format
        || old.auto_start != new.auto_start
}

fn read_json_or_empty<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> Result<T> {
    if !path.exists() {
        return Ok(T::default());
    }
    let data =
        fs::read_to_string(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_str(&data).with_context(|| format!("failed to parse {}", path.display()))
}
