use anyhow::{bail, Context, Result};
use clap::Subcommand;
use neet_core::manifest::Core;
use nix::unistd::{Group, Uid, User};
use std::ffi::OsString;
use std::fs;
use std::path::{Path, PathBuf};
use std::process::Command;

const STORE: &str = "/nix/store";
const PROFILE: &str = "/nix/var/nix/profiles/system";

#[derive(Subcommand, Debug)]
pub enum PrivOp {
    /// profile 更新 → bootloader → 再起動要否判定 → activate → s6-rc-update
    Switch {
        toplevel: PathBuf,
        #[arg(long)]
        force: bool,
    },
    /// profile 更新 → bootloader のみ
    Boot { toplevel: PathBuf },
}

impl PrivOp {
    fn to_args(&self) -> Vec<OsString> {
        match self {
            PrivOp::Switch { toplevel, force } => {
                let mut v = vec!["switch".into(), toplevel.clone().into_os_string()];
                if *force {
                    v.push("--force".into());
                }
                v
            }
            PrivOp::Boot { toplevel } => {
                vec!["boot".into(), toplevel.clone().into_os_string()]
            }
        }
    }
}

// ───────────── クライアント側 ─────────────

/// root ならそのまま実行、そうでなければ s6-sudo 経由で `neet priv ...` を呼ぶ
pub fn invoke(op: &PrivOp) -> Result<()> {
    if Uid::current().is_root() {
        return execute(op);
    }

    let sock = std::env::var("NEET_ADMIN_SOCK").unwrap_or_else(|_| "/run/neet-admin/sock".into());
    let s6_sudo = std::env::var("NEET_S6_SUDO").unwrap_or_else(|_| "s6-sudo".into());

    let status = Command::new(&s6_sudo)
        .arg(&sock)
        .args(op.to_args())
        .status()
        .with_context(|| {
            format!(
                "Failed to execute {} (is neet-admin-server running?)",
                s6_sudo
            )
        })?;

    if !status.success() {
        bail!("privileged operation failed: {}", status);
    }
    Ok(())
}

// ───────────── サーバ (root) 側 ─────────────

/// `neet priv ...` のエントリ。s6-sudod から起動される。
pub fn serve(op: PrivOp) -> Result<()> {
    if !Uid::current().is_root() {
        bail!("neet priv must run as root (via neet-admin-server)");
    }
    let uid = authorize()?;
    eprintln!("[neet-priv] uid={} op={:?}", uid, op);
    execute(&op)
}

/// 接続元 uid が root か許可グループのメンバーであることを確認する。
/// ソケットのディレクトリ権限に対する二重チェック。
fn authorize() -> Result<u32> {
    // s6-ipcserver が接続元 uid を環境変数で渡してくる
    let uid = std::env::var("IPCREMOTEEUID")
        .ok()
        .and_then(|s| s.parse::<u32>().ok())
        .unwrap_or_else(|| Uid::current().as_raw());

    if uid == 0 {
        return Ok(uid);
    }

    let group_name = std::env::var("NEET_ALLOWED_GROUP").unwrap_or_else(|_| "wheel".into());
    let user =
        User::from_uid(Uid::from_raw(uid))?.with_context(|| format!("unknown uid {}", uid))?;
    let group = Group::from_name(&group_name)?
        .with_context(|| format!("group '{}' not found", group_name))?;

    if user.gid == group.gid || group.mem.iter().any(|m| m == &user.name) {
        Ok(uid)
    } else {
        bail!("uid {} is not in group '{}'", uid, group_name);
    }
}

/// toplevel は /nix/store 直下のパスでなければならない（symlink も解決して確認）
fn validate_toplevel(p: &Path) -> Result<PathBuf> {
    let real = fs::canonicalize(p).with_context(|| format!("cannot resolve {}", p.display()))?;
    if real.parent() != Some(Path::new(STORE)) {
        bail!(
            "toplevel must be a direct child of {}: {}",
            STORE,
            real.display()
        );
    }
    Ok(real)
}

fn run(mut cmd: Command) -> Result<()> {
    let name = cmd.get_program().to_string_lossy().into_owned();
    let status = cmd
        .status()
        .with_context(|| format!("Failed to execute {}", name))?;
    if !status.success() {
        bail!("'{}' failed with exit status: {}", name, status);
    }
    Ok(())
}

fn set_profile(toplevel: &Path) -> Result<()> {
    println!("==> [neet] Updating system profile...");
    let mut c = Command::new("nix-env");
    c.args(["-p", PROFILE, "--set"]).arg(toplevel);
    run(c)
}

fn install_bootloader(toplevel: &Path) -> Result<()> {
    let bootloader = toplevel.join("bin/install-bootloader");
    if bootloader.exists() {
        println!("==> [neet] Updating bootloader...");
        // 失敗したら中断する (以前は握りつぶしていた)
        run(Command::new(&bootloader)).context("bootloader update failed")?;
    }
    Ok(())
}

fn execute(op: &PrivOp) -> Result<()> {
    match op {
        PrivOp::Boot { toplevel } => {
            let toplevel = validate_toplevel(toplevel)?;
            Core::load(&toplevel).context("not a valid NEET OS toplevel")?;
            set_profile(&toplevel)?;
            install_bootloader(&toplevel)?;
            println!("==> [neet] Boot configuration updated. Will take effect on next reboot.");
            Ok(())
        }

        PrivOp::Switch { toplevel, force } => {
            let toplevel = validate_toplevel(toplevel)?;
            let core = Core::load(&toplevel).context("not a valid NEET OS toplevel")?;

            set_profile(&toplevel)?;
            install_bootloader(&toplevel)?;

            if let Some(reason) = crate::diff::reboot::check_reboot_required(&core)? {
                if !*force {
                    println!("--------------------------------------------------");
                    println!(" [NOTICE] Live switch skipped: {}", reason);
                    println!(" Bootloader is updated. Please reboot your system!");
                    println!(" (To force live switch anyway, use --force)");
                    println!("--------------------------------------------------");
                    return Ok(());
                }
                println!("==> [neet] Forcing live switch despite reboot notice...");
            }

            println!("==> [neet] Activating live configuration...");
            let mut c = Command::new("neet-activate");
            c.arg("switch").arg(&core.path);
            run(c)?;

            let live_s6 = Path::new("/run/s6-rc");
            if let Some(s6_db) = core.s6_rc() {
                if live_s6.exists() {
                    println!("==> [neet] Updating system s6-rc service database...");
                    let mut c = Command::new("s6-rc-update");
                    c.args(["-l", "/run/s6-rc"]).arg(&s6_db);
                    run(c).context("activation succeeded but s6-rc-update failed")?;
                }
            }

            println!("==> [neet] Successfully switched to new configuration!");
            Ok(())
        }
    }
}
