use anyhow::Result;
use colored::*;
use serde::Deserialize;
use std::collections::{HashMap, HashSet};
use std::fs;
use std::path::Path;

#[derive(Debug, Deserialize, PartialEq, Eq)]
pub struct S6ServiceMeta {
    pub r#type: String,
    pub dependencies: Vec<String>,
    #[serde(rename = "autoStart")]
    pub auto_start: bool,
    #[serde(rename = "scriptHash")]
    pub script_hash: Option<String>,
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
        read_json_or_empty(&old_etc.join("s6-rc/services.json"));
    let new_map: HashMap<String, S6ServiceMeta> =
        read_json_or_empty(&new_etc.join("s6-rc/services.json"));
    diff_service_maps(&old_map, &new_map, "  ")
}

pub fn diff_user_s6(old_etc: &Path, new_etc: &Path) -> Result<bool> {
    let old_users: HashMap<String, UserMeta> =
        read_json_or_empty(&old_etc.join("s6-rc/users-services.json"));
    let new_users: HashMap<String, UserMeta> =
        read_json_or_empty(&new_etc.join("s6-rc/users-services.json"));

    let mut changed = false;
    let all_users: HashSet<_> = old_users.keys().chain(new_users.keys()).collect();

    // ★ ループの外で型を明示して定義
    let empty_services: HashMap<String, S6ServiceMeta> = HashMap::new();

    for user in all_users {
        let user_meta = new_users.get(user).or_else(|| old_users.get(user));

        // uid / gid があれば表示に含める（これで両方参照され警告も消えます）
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

        if diff_service_maps(old_svcs, new_svcs, "  ")? {
            changed = true;
        }
    }
    Ok(changed)
}

fn diff_service_maps(
    old_map: &HashMap<String, S6ServiceMeta>,
    new_map: &HashMap<String, S6ServiceMeta>,
    indent: &str,
) -> Result<bool> {
    let old_keys: HashSet<_> = old_map.keys().collect();
    let new_keys: HashSet<_> = new_map.keys().collect();
    let mut has_diff = false;

    for name in new_keys.difference(&old_keys) {
        has_diff = true;
        let svc = &new_map[*name];
        println!(
            "{}{} {} (autoStart: {})",
            indent,
            "[+]".green().bold(),
            name,
            svc.auto_start
        );
    }

    for name in old_keys.difference(&new_keys) {
        has_diff = true;
        println!("{}{} {}", indent, "[-]".red().bold(), name);
    }

    for name in old_keys.intersection(&new_keys) {
        let old = &old_map[*name];
        let new = &new_map[*name];
        if old != new {
            has_diff = true;
            let mut details = Vec::new();
            if old.script_hash != new.script_hash {
                details.push("script modified");
            }
            if old.dependencies != new.dependencies {
                details.push("dependencies changed");
            }
            if old.auto_start != new.auto_start {
                details.push(if new.auto_start {
                    "enabled"
                } else {
                    "disabled"
                });
            }
            println!(
                "{}{} {} ({})",
                indent,
                "[~]".yellow().bold(),
                name,
                details.join(", ")
            );
        }
    }

    if !has_diff {
        println!("{}(no changes)", indent);
    }
    Ok(has_diff)
}

fn read_json_or_empty<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> T {
    fs::read_to_string(path)
        .ok()
        .and_then(|data| serde_json::from_str(&data).ok())
        .unwrap_or_default()
}
