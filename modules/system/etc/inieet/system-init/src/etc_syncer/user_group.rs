use nix::unistd::{Gid, Uid};
use std::fs;
use std::io;

/// /etc/passwd から抽出したユーザー情報
#[derive(Debug)]
pub struct UserEntry {
    pub username: String,
    pub uid: Uid,
    pub gid: Gid,
    pub home: String,
}

/// /etc/passwd 全体をパースして全ユーザーのリストを取得
pub fn parse_passwd() -> io::Result<Vec<UserEntry>> {
    let contents = fs::read_to_string("/etc/passwd")?;
    let mut users = Vec::new();

    for line in contents.lines() {
        if line.starts_with('#') || line.trim().is_empty() {
            continue;
        }

        let parts: Vec<&str> = line.split(':').collect();
        if parts.len() >= 6 {
            let username = parts[0].to_string();
            let uid = parts[2]
                .parse::<u32>()
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
            let gid = parts[3]
                .parse::<u32>()
                .map_err(|e| io::Error::new(io::ErrorKind::InvalidData, e))?;
            let home = parts[5].to_string();

            users.push(UserEntry {
                username,
                uid: Uid::from_raw(uid),
                gid: Gid::from_raw(gid),
                home,
            });
        }
    }
    Ok(users)
}

pub fn resolve_uid(spec: &str) -> Option<u32> {
    match spec.strip_prefix('+') {
        Some(n) => n.parse().ok(),
        None => lookup_passwd_uid(spec),
    }
}

pub fn resolve_gid(spec: &str) -> Option<u32> {
    match spec.strip_prefix('+') {
        Some(n) => n.parse().ok(),
        None => lookup_group_gid(spec),
    }
}

fn lookup_passwd_uid(name: &str) -> Option<u32> {
    let contents = fs::read_to_string("/etc/passwd").ok()?;
    contents.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok()
    })
}

fn lookup_group_gid(name: &str) -> Option<u32> {
    let contents = fs::read_to_string("/etc/group").ok()?;
    contents.lines().find_map(|line| {
        let mut fields = line.split(':');
        if fields.next()? != name {
            return None;
        }
        fields.nth(1)?.parse().ok()
    })
}
