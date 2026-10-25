use std::fs;

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
