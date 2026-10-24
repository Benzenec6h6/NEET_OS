//! neet-mount: mount-plan.json の解釈とマウント実行（stage1 / stage2 共通）
//!
//! 方針:
//! - bind マウントの失敗は致命的エラーとして呼び出し側に返す
//!   （黙って続行すると、書き込みが揮発するルート側に入りデータを失うため）
//! - btrfs の resetOnBoot は旧ルートを削除せず `old_roots/` に退避し、
//!   `keepOldRoots` 世代を超えたものだけを古い順に削除する

mod btrfs_reset;
mod mount;
mod plan;
mod util;

pub use mount::apply_plan;
pub use plan::{load_plan, MountEntry};
