use crate::util::fatal;
use nix::mount::{mount, umount2, MntFlags, MsFlags};
use std::fs;
use std::io;
use std::path::{Path, PathBuf};

/// スコープを抜けると自動的にアンマウント＆ディレクトリ掃除を行う RAII ガード
#[derive(Debug)]
pub struct OverlayGuard {
    target: PathBuf,
    temp_dir: PathBuf,
}

impl OverlayGuard {
    /// 指定されたターゲットパス（例: /etc）に tmpfs upper の OverlayFS を被せる
    pub fn mount_temp(target: impl AsRef<Path>) -> io::Result<Self> {
        let target = target
            .as_ref()
            .canonicalize()
            .unwrap_or_else(|_| target.as_ref().to_path_buf());

        // /tmp (tmpfs) 配下に固有の一時ディレクトリを作成
        // ※ 複数同時に被せる（/etc と /var/lib/s6-rc など）場合もあるのでパスの末尾を名前に含める
        let safe_name = target.to_string_lossy().replace('/', "_");
        let rand_id = std::process::id();
        let temp_dir = PathBuf::from(format!("/tmp/neet-overlay{safe_name}-{rand_id}"));
        let upper_dir = temp_dir.join("upper");
        let work_dir = temp_dir.join("work");

        fs::create_dir_all(&upper_dir)?;
        fs::create_dir_all(&work_dir)?;

        let lower = target.display();
        let upper = upper_dir.display();
        let work = work_dir.display();
        let opts = format!("lowerdir={lower},upperdir={upper},workdir={work}");

        println!(
            "neet-mount: mounting temporary overlay on {}",
            target.display()
        );

        mount(
            Some("overlay"),
            &target,
            Some("overlay"),
            MsFlags::empty(),
            Some(opts.as_str()),
        )
        .map_err(|e| {
            fatal(format!(
                "failed to mount overlay on {}: {e}",
                target.display()
            ))
        })?;

        Ok(Self { target, temp_dir })
    }

    /// 明示的に即座にアンマウントして片付けたい場合
    pub fn unmount(mut self) -> io::Result<()> {
        self.cleanup()
    }

    fn cleanup(&mut self) -> io::Result<()> {
        if self.temp_dir.exists() {
            println!(
                "neet-mount: unmounting temporary overlay from {}",
                self.target.display()
            );

            // プロセスがファイルを開いている可能性を考慮し、失敗時は MNT_DETACH (lazy umount)
            if umount2(&self.target, MntFlags::empty()).is_err() {
                let _ = umount2(&self.target, MntFlags::MNT_DETACH);
            }

            // 作業用ディレクトリの破棄
            let _ = fs::remove_dir_all(&self.temp_dir);
        }
        Ok(())
    }
}

impl Drop for OverlayGuard {
    fn drop(&mut self) {
        let _ = self.cleanup();
    }
}
