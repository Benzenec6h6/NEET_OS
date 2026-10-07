//! disk-setup CLI
//!
//! disk-setup format <plan.json> [--disk NAME] [--device DEV] [--yes] [--force]
//! disk-setup mount  <plan.json> <root> [--disk NAME --device DEV]
//! disk-setup image  <plan.json> --out FILE --size-m N [--disk NAME] --tree DIR... [--work DIR]

use disk_setup::exec::{format_disk, mount_plan, FormatOpts};
use disk_setup::image::{build_image, ImageOpts};
use disk_setup::plan::Plan;
use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::process::exit;

const VALUE_FLAGS: &[&str] = &["--disk", "--device", "--out", "--size-m", "--tree", "--work"];
const SWITCH_FLAGS: &[&str] = &["--yes", "--force"];

#[derive(Default)]
struct Args {
    positional: Vec<String>,
    values: HashMap<String, Vec<String>>,
    switches: Vec<String>,
}

impl Args {
    fn parse(raw: &[String]) -> Result<Args, String> {
        let mut a = Args::default();
        let mut it = raw.iter();
        while let Some(arg) = it.next() {
            if VALUE_FLAGS.contains(&arg.as_str()) {
                let v = it.next().ok_or(format!("{arg} requires a value"))?;
                a.values.entry(arg.clone()).or_default().push(v.clone());
            } else if SWITCH_FLAGS.contains(&arg.as_str()) {
                a.switches.push(arg.clone());
            } else if arg.starts_with("--") {
                return Err(format!("unknown option {arg}"));
            } else {
                a.positional.push(arg.clone());
            }
        }
        Ok(a)
    }
    fn one(&self, k: &str) -> Option<&str> {
        self.values.get(k).and_then(|v| v.last()).map(String::as_str)
    }
    fn many(&self, k: &str) -> Vec<String> {
        self.values.get(k).cloned().unwrap_or_default()
    }
    fn on(&self, k: &str) -> bool {
        self.switches.iter().any(|s| s == k)
    }
}

fn usage() -> ! {
    eprintln!(
        "usage:\n  disk-setup format <plan.json> [--disk NAME] [--device DEV] [--yes] [--force]\n  \
         disk-setup mount  <plan.json> <root> [--disk NAME --device DEV]\n  \
         disk-setup image  <plan.json> --out FILE --size-m N [--disk NAME] --tree DIR... [--work DIR]"
    );
    exit(2)
}

fn die(msg: impl std::fmt::Display) -> ! {
    eprintln!("disk-setup: fatal: {msg}");
    exit(1)
}

fn main() {
    let raw: Vec<String> = std::env::args().skip(1).collect();
    let Some((cmd, rest)) = raw.split_first() else { usage() };
    let args = Args::parse(rest).unwrap_or_else(|e| die(e));
    let Some(plan_path) = args.positional.first() else { usage() };
    let plan = Plan::load(Path::new(plan_path)).unwrap_or_else(|e| die(format!("{plan_path}: {e}")));

    match cmd.as_str() {
        "format" => {
            let disk = plan.select_disk(args.one("--disk")).unwrap_or_else(|e| die(e));
            let opts = FormatOpts {
                device: args.one("--device").map(String::from),
                yes: args.on("--yes"),
                force: args.on("--force"),
            };
            format_disk(disk, &opts).unwrap_or_else(|e| die(e));
        }
        "mount" => {
            let Some(root) = args.positional.get(1) else { usage() };
            let ov = match args.one("--device") {
                Some(dev) => {
                    let d = plan.select_disk(args.one("--disk")).unwrap_or_else(|e| die(e));
                    Some((d.name.as_str(), dev))
                }
                None => None,
            };
            mount_plan(&plan, Path::new(root), ov).unwrap_or_else(|e| die(e));
        }
        "image" => {
            let out = args.one("--out").unwrap_or_else(|| usage());
            let size_m: u64 = args
                .one("--size-m")
                .and_then(|s| s.parse().ok())
                .unwrap_or_else(|| usage());
            let work = args
                .one("--work")
                .map(PathBuf::from)
                .unwrap_or_else(|| std::env::temp_dir().join(format!("disk-setup-image-{}", std::process::id())));
            let opts = ImageOpts {
                disk: args.one("--disk").map(String::from),
                size_bytes: size_m * 1024 * 1024,
                trees: args.many("--tree").into_iter().map(PathBuf::from).collect(),
                out: PathBuf::from(out),
                work,
            };
            build_image(&plan, &opts).unwrap_or_else(|e| die(e));
        }
        _ => usage(),
    }
}
