use anyhow::{Context, Result};
use colored::*;
use serde::Deserialize;
use std::collections::{BTreeMap, BTreeSet, HashMap};
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

struct TreeNode {
    label: String,
    children: Vec<TreeNode>,
}

impl TreeNode {
    fn leaf(label: impl Into<String>) -> Self {
        Self {
            label: label.into(),
            children: Vec::new(),
        }
    }
}

pub fn diff_system_s6(old_etc: &Path, new_etc: &Path) -> Result<bool> {
    println!("{}", "[s6-rc System Services]".bold());
    let old_map: HashMap<String, S6ServiceMeta> =
        read_json_or_empty(&old_etc.join("s6-rc/services.json"))?;
    let new_map: HashMap<String, S6ServiceMeta> =
        read_json_or_empty(&new_etc.join("s6-rc/services.json"))?;
    diff_service_tree(&old_map, &new_map, "  ")
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

        if diff_service_tree(old_svcs, new_svcs, "  ")? {
            changed = true;
        }
    }
    Ok(changed)
}

fn diff_service_tree(
    old_map: &HashMap<String, S6ServiceMeta>,
    new_map: &HashMap<String, S6ServiceMeta>,
    indent: &str,
) -> Result<bool> {
    let all_names: BTreeSet<&String> = old_map.keys().chain(new_map.keys()).collect();

    // 逆依存マップ（このサービスに依存しているサービス一覧）を作成
    let mut dependents: HashMap<&str, BTreeSet<&str>> = HashMap::new();
    for (svc_name, meta) in new_map {
        for dep in &meta.dependencies {
            dependents
                .entry(dep.as_str())
                .or_default()
                .insert(svc_name.as_str());
        }
    }

    // バンドル名 -> 変更があったサービスノード一覧
    // BTreeMap を使うことで出力順を安定させる
    let mut bundles: BTreeMap<String, Vec<TreeNode>> = BTreeMap::new();

    for name in all_names {
        let old = old_map.get(name);
        let new = new_map.get(name);

        let Some(node) = build_service_node(name, old, new, &dependents) else {
            continue;
        };

        // 所属バンドルを決定（変更前・後のいずれかに属していれば表示）
        let target_bundles = collect_bundles(old, new);
        for b in target_bundles {
            bundles.entry(b).or_default().push(clone_node(&node));
        }
    }

    if bundles.is_empty() {
        println!("{}(no changes)", indent);
        return Ok(false);
    }

    // 表示優先度: top -> graphical-session -> その他 -> (manual)
    let mut ordered: Vec<(String, Vec<TreeNode>)> = Vec::new();
    for priority in ["top", "graphical-session"] {
        if let Some(nodes) = bundles.remove(priority) {
            ordered.push((format_bundle_header(priority), nodes));
        }
    }
    let manual = bundles.remove("(manual)");
    for (b, nodes) in bundles {
        ordered.push((format_bundle_header(&b), nodes));
    }
    if let Some(nodes) = manual {
        ordered.push((format_bundle_header("(manual)"), nodes));
    }

    let root_nodes: Vec<TreeNode> = ordered
        .into_iter()
        .map(|(label, children)| TreeNode { label, children })
        .collect();

    render_tree(&root_nodes, indent);
    Ok(true)
}

fn build_service_node(
    name: &str,
    old: Option<&S6ServiceMeta>,
    new: Option<&S6ServiceMeta>,
    dependents: &HashMap<&str, BTreeSet<&str>>,
) -> Option<TreeNode> {
    match (old, new) {
        (None, Some(n)) => {
            let mut children = Vec::new();
            if !n.dependencies.is_empty() {
                children.push(TreeNode::leaf(format!(
                    "{}: {}",
                    "deps".dimmed(),
                    n.dependencies.join(", ")
                )));
            }
            if !n.envdirs.is_empty() {
                children.push(TreeNode::leaf(format!(
                    "{}: {}",
                    "envdirs".dimmed(),
                    n.envdirs.join(", ")
                )));
            }
            if n.logger_hash.is_some() {
                children.push(TreeNode::leaf(format!("{}: enabled", "logger".dimmed())));
            }
            Some(TreeNode {
                label: format!("{} {} ({})", "[+]".green().bold(), name.bold(), n.r#type),
                children,
            })
        }
        (Some(o), None) => {
            let mut children = Vec::new();
            if let Some(deps) = dependents.get(name) {
                let list: Vec<_> = deps.iter().copied().collect();
                children.push(TreeNode::leaf(format!(
                    "{}: {}",
                    "was depended by".red(),
                    list.join(", ")
                )));
            }
            Some(TreeNode {
                label: format!("{} {} ({})", "[-]".red().bold(), name, o.r#type),
                children,
            })
        }
        (Some(o), Some(n)) => {
            let mut children = Vec::new();

            if o.r#type != n.r#type {
                children.push(TreeNode::leaf(format!(
                    "type: {} -> {}",
                    o.r#type.red(),
                    n.r#type.green()
                )));
            }
            if o.script_hash != n.script_hash {
                children.push(TreeNode::leaf("script: modified".yellow().to_string()));
            }
            if o.logger_hash != n.logger_hash {
                let msg = match (&o.logger_hash, &n.logger_hash) {
                    (None, Some(_)) => "logger: enabled".green().to_string(),
                    (Some(_), None) => "logger: disabled".red().to_string(),
                    _ => "logger: modified".yellow().to_string(),
                };
                children.push(TreeNode::leaf(msg));
            }
            if o.auto_start != n.auto_start {
                let msg = if n.auto_start {
                    "autoStart: false -> true (added to top)".green()
                } else {
                    "autoStart: true -> false (removed from top)".yellow()
                };
                children.push(TreeNode::leaf(msg.to_string()));
            }
            if o.notification_fd != n.notification_fd {
                children.push(TreeNode::leaf(format!(
                    "notification-fd: {:?} -> {:?}",
                    o.notification_fd, n.notification_fd
                )));
            }
            if o.format != n.format {
                children.push(TreeNode::leaf(format!(
                    "format: {} -> {}",
                    o.format.as_deref().unwrap_or("?"),
                    n.format.as_deref().unwrap_or("?")
                )));
            }

            push_set_diff(&mut children, "deps", &o.dependencies, &n.dependencies);
            push_set_diff(&mut children, "envdirs", &o.envdirs, &n.envdirs);
            push_set_diff(&mut children, "partOf", &o.part_of, &n.part_of);

            if children.is_empty() {
                return None;
            }

            // 変更があるときだけ逆依存（影響範囲）を添える
            if let Some(deps) = dependents.get(name) {
                let list: Vec<_> = deps.iter().copied().collect();
                children.push(TreeNode::leaf(format!(
                    "{}: {}",
                    "affects".cyan(),
                    list.join(", ")
                )));
            }

            Some(TreeNode {
                label: format!("{} {} ({})", "[~]".yellow().bold(), name.bold(), n.r#type),
                children,
            })
        }
        (None, None) => None,
    }
}

fn push_set_diff(children: &mut Vec<TreeNode>, label: &str, old: &[String], new: &[String]) {
    let old_set: BTreeSet<&str> = old.iter().map(|s| s.as_str()).collect();
    let new_set: BTreeSet<&str> = new.iter().map(|s| s.as_str()).collect();

    let mut parts = Vec::new();
    for added in new_set.difference(&old_set) {
        parts.push(format!("+{}", added).green().to_string());
    }
    for removed in old_set.difference(&new_set) {
        parts.push(format!("-{}", removed).red().to_string());
    }

    if !parts.is_empty() {
        children.push(TreeNode::leaf(format!("{}: {}", label, parts.join(", "))));
    }
}

fn collect_bundles(old: Option<&S6ServiceMeta>, new: Option<&S6ServiceMeta>) -> BTreeSet<String> {
    let mut set = BTreeSet::new();
    for meta in [old, new].into_iter().flatten() {
        if meta.auto_start {
            set.insert("top".to_string());
        }
        for b in &meta.part_of {
            set.insert(b.clone());
        }
    }
    if set.is_empty() {
        set.insert("(manual)".to_string());
    }
    set
}

fn format_bundle_header(name: &str) -> String {
    match name {
        "top" => format!("{} {}", "top".bold().blue(), "(boot)".dimmed()),
        "graphical-session" => format!("{}", "graphical-session".bold().magenta()),
        "(manual)" => format!("{}", "(manual / unbundled)".dimmed()),
        other => format!("{}", other.bold()),
    }
}

fn render_tree(nodes: &[TreeNode], prefix: &str) {
    for (idx, node) in nodes.iter().enumerate() {
        let is_last = idx + 1 == nodes.len();
        let branch = if is_last { "└── " } else { "├── " };
        println!("{}{}{}", prefix, branch, node.label);

        if !node.children.is_empty() {
            let next_prefix = format!("{}{}", prefix, if is_last { "    " } else { "│   " });
            render_tree(&node.children, &next_prefix);
        }
    }
}

fn clone_node(node: &TreeNode) -> TreeNode {
    TreeNode {
        label: node.label.clone(),
        children: node.children.iter().map(clone_node).collect(),
    }
}

fn read_json_or_empty<T: for<'de> Deserialize<'de> + Default>(path: &Path) -> Result<T> {
    if !path.exists() {
        return Ok(T::default());
    }
    let data =
        fs::read_to_string(path).with_context(|| format!("failed to read {}", path.display()))?;
    serde_json::from_str(&data).with_context(|| format!("failed to parse {}", path.display()))
}
